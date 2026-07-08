import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/protocol.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/network/local_ip.dart';
import '../../../core/protocol/device_info.dart';
import '../domain/discovered_device.dart';

/// LAN discovery over mDNS/Bonjour (`_bishare._tcp`).
///
/// Advertises this device (TXT includes the self-reported `ip`) and browses for
/// peers, exposing a live [devices] stream. Address resolution trusts the peer's
/// self-reported TXT `ip` over the transport-resolved host — this is the fix that
/// makes Apple↔Apple discovery reliable (avoids unreachable AWDL IPv6 link-local).
class DiscoveryService {
  DiscoveryService(this._identity);

  final DeviceIdentity _identity;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  Timer? _staleTimer;
  Timer? _keepAliveTimer;
  bool _probing = false;
  bool _refreshing = false;

  final Map<String, DiscoveredDevice> _devices = {};

  /// Consecutive failed keep-alive probes per fingerprint; a device is dropped
  /// after [_maxMisses] so a brief Wi-Fi hiccup doesn't evict a live peer.
  final Map<String, int> _misses = {};
  static const _maxMisses = 3;
  final StreamController<List<DiscoveredDevice>> _controller =
      StreamController<List<DiscoveredDevice>>.broadcast();

  /// Live list of currently-visible peers (excludes this device).
  Stream<List<DiscoveredDevice>> get devices => _controller.stream;

  List<DiscoveredDevice> get current => _devices.values.toList(growable: false);

  bool get isRunning => _discovery != null;

  /// Starts advertising + browsing. Safe to call once; call [stop] first to restart.
  Future<void> start() async {
    if (_discovery != null) return;
    final info = await _identity.makeDeviceInfo();

    _broadcast = BonsoirBroadcast(service: _serviceFor(info));
    await _broadcast!.initialize();
    await _broadcast!.start();

    final discovery = BonsoirDiscovery(type: BIShareService.discovery);
    _discovery = discovery;
    await discovery.initialize();
    _sub = discovery.eventStream?.listen(_onEvent);
    await discovery.start();

    _staleTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sweepStale(),
    );

    // mDNS fires ServiceResolved once and rarely re-announces, so `lastSeen`
    // would never refresh and live peers would be swept as stale (they'd vanish
    // after a few seconds). A lightweight keep-alive re-probes each known peer's
    // `/api/v1/info`: it refreshes lastSeen, picks up rename (alias updates in
    // place, keyed by the canonical fingerprint), and evicts genuinely-dead
    // peers by miss-count. It also collapses duplicates by IP.
    _keepAliveTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshKnown()),
    );

    // mDNS can be blocked (multicast entitlement, VPN, some Wi-Fi APs). If nothing
    // shows up shortly, fall back to a subnet /24 unicast probe.
    Timer(const Duration(seconds: 3), () {
      if (_devices.isEmpty && _discovery != null) unawaited(probeSubnet());
    });
  }

  Future<void> stop() async {
    _staleTimer?.cancel();
    _staleTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _discovery?.stop();
    _discovery = null;
    await _broadcast?.stop();
    _broadcast = null;
    _devices.clear();
    _misses.clear();
    _emit();
  }

  /// Stop then start — refreshes advertisement + browse (e.g. on app resume).
  Future<void> restart() async {
    await stop();
    await start();
  }

  BonsoirService _serviceFor(DeviceInfo info) => BonsoirService(
    name: info.fingerprint,
    type: BIShareService.discovery,
    port: BISharePort.main,
    attributes: {
      'ip': info.ip ?? '',
      'alias': info.alias,
      'model': info.deviceModel ?? '',
      'deviceType': info.deviceType ?? 'mobile',
      'version': info.version,
      'fingerprint': info.fingerprint,
      'port': '${BISharePort.main}',
      // Advertise the QUIC port on EVERY platform so a QUIC sender can always
      // reach us — the transport is symmetric (the sender's choice = the
      // receiver's). We run both a TCP and a QUIC server and accept whichever
      // stream the sender opens. (Auto still prefers TCP on the LAN; QUIC is an
      // explicit opt-in and the transport for the future remote/relay path.)
      'quicPort': '${BISharePort.quic}',
    },
  );

  /// Toggle only the mDNS advertisement (browsing continues) — the "Hidden"
  /// visibility setting.
  Future<void> setAdvertising(bool advertise) async {
    if (advertise) {
      if (_broadcast != null || _discovery == null) return;
      final info = await _identity.makeDeviceInfo();
      _broadcast = BonsoirBroadcast(service: _serviceFor(info));
      await _broadcast!.initialize();
      await _broadcast!.start();
    } else {
      await _broadcast?.stop();
      _broadcast = null;
    }
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        // Resolve to obtain host addresses + TXT attributes.
        unawaited(
          Future.sync(
            () => _discovery?.serviceResolver.resolveService(service),
          ),
        );
      case BonsoirDiscoveryServiceResolvedEvent(:final service) ||
          BonsoirDiscoveryServiceUpdatedEvent(:final service):
        _upsert(service);
      case BonsoirDiscoveryServiceLostEvent(:final service):
        _remove(service);
      default:
        break;
    }
  }

  void _upsert(BonsoirService service) {
    final attrs = service.attributes;
    final fingerprint = attrs['fingerprint'] ?? service.name;
    if (fingerprint == _identity.fingerprint) return; // skip self

    final host = _resolveHost(attrs, service.hostAddresses);
    if (host == null) return; // unreachable — no usable IPv4

    final port = int.tryParse(attrs['port'] ?? '') ?? service.port;
    final quicPort = int.tryParse(attrs['quicPort'] ?? '');

    final alias = attrs['alias']?.isNotEmpty == true
        ? attrs['alias']!
        : fingerprint;
    _devices[fingerprint] = DiscoveredDevice(
      fingerprint: fingerprint,
      alias: alias,
      host: host,
      port: port,
      lastSeen: DateTime.now(),
      deviceModel: attrs['model'] ?? '',
      deviceType: attrs['deviceType'] ?? 'mobile',
      version: attrs['version'] ?? '2.0',
      quicPort: quicPort,
    );
    _misses.remove(fingerprint);
    _dedupeByHost(fingerprint, host);
    debugPrint(
      '[Discovery] peer "$alias" @ $host:$port (v${attrs['version']}, ip-src=${attrs.containsKey('ip') ? 'txt' : 'resolved'})',
    );
    _emit();
  }

  void _remove(BonsoirService service) {
    final fingerprint = service.attributes['fingerprint'] ?? service.name;
    if (_devices.remove(fingerprint) != null) _emit();
  }

  /// Remove a peer by fingerprint (used when a peer sends `goodbye`).
  void removeByFingerprint(String fingerprint) {
    if (_devices.remove(fingerprint) != null) _emit();
  }

  /// Fallback discovery: probe every host on the local /24 with `GET /api/v1/info`
  /// in bounded-parallel batches. Adds any BIShare responder. Used when mDNS is
  /// blocked/slow (multicast entitlement, VPN, restrictive Wi-Fi APs).
  Future<void> probeSubnet() async {
    if (_probing) return;
    _probing = true;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: 700),
        receiveTimeout: const Duration(milliseconds: 700),
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );
    try {
      final selfIp = await LocalIp.resolve();
      final lastDot = selfIp.lastIndexOf('.');
      if (lastDot < 0) return;
      final base = selfIp.substring(0, lastDot); // e.g. "192.168.100"
      final selfHost = int.tryParse(selfIp.substring(lastDot + 1));
      const batch = 40;
      for (var start = 1; start <= 254; start += batch) {
        final futures = <Future<void>>[];
        for (var h = start; h < start + batch && h <= 254; h++) {
          if (h == selfHost) continue;
          futures.add(_probeHost(dio, '$base.$h'));
        }
        await Future.wait(futures);
      }
    } finally {
      dio.close(force: true);
      _probing = false;
    }
  }

  Future<void> _probeHost(Dio dio, String host) async {
    try {
      final res = await dio.get<Map<String, dynamic>>(
        'http://$host:${BISharePort.main}${BIShareApi.info}',
      );
      if (res.statusCode != BIShareStatus.ok || res.data == null) return;
      final info = DeviceInfo.fromJson(res.data!);
      if (info.fingerprint == _identity.fingerprint) return;
      final resolvedHost = (info.ip != null && _isUsableIPv4(info.ip!))
          ? info.ip!
          : host;
      _devices[info.fingerprint] = DiscoveredDevice(
        fingerprint: info.fingerprint,
        alias: info.alias.isNotEmpty ? info.alias : info.fingerprint,
        host: resolvedHost,
        port: info.port,
        lastSeen: DateTime.now(),
        deviceModel: info.deviceModel ?? '',
        deviceType: info.deviceType ?? 'mobile',
        version: info.version,
      );
      _misses.remove(info.fingerprint);
      _dedupeByHost(info.fingerprint, resolvedHost);
      debugPrint('[Discovery] probe found "${info.alias}" @ $resolvedHost');
      _emit();
    } on Object {
      // Not a BIShare peer / unreachable — ignore.
    }
  }

  /// Prefer the peer's self-reported IPv4 (TXT `ip`); fall back to the first
  /// resolved IPv4 host address. Reject loopback/link-local/IPv6.
  String? _resolveHost(Map<String, String> attrs, List<String> hostAddresses) {
    final reported = attrs['ip'];
    if (reported != null && _isUsableIPv4(reported)) return reported;
    for (final addr in hostAddresses) {
      if (_isUsableIPv4(addr)) return addr;
    }
    return null;
  }

  static bool _isUsableIPv4(String ip) {
    if (ip.isEmpty || ip.contains(':')) return false;
    if (ip == '127.0.0.1' || ip == '0.0.0.0') return false;
    if (ip.startsWith('169.254.')) return false;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  /// Removes any peer other than [keepFingerprint] that shares [host] — one
  /// physical device = one IP, so a stale entry (e.g. an old cached alias) can't
  /// linger alongside the fresh one.
  void _dedupeByHost(String keepFingerprint, String host) {
    _devices.removeWhere((fp, d) => fp != keepFingerprint && d.host == host);
  }

  /// Keep-alive: re-probe every known peer's `/api/v1/info` to refresh liveness,
  /// pick up renames, and evict dead peers by miss-count.
  Future<void> _refreshKnown() async {
    if (_refreshing || _devices.isEmpty || _discovery == null) return;
    _refreshing = true;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: 900),
        receiveTimeout: const Duration(milliseconds: 900),
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );
    try {
      final snapshot = _devices.values.toList(growable: false);
      await Future.wait(snapshot.map((d) => _refreshOne(dio, d)));
    } finally {
      dio.close(force: true);
      _refreshing = false;
    }
  }

  Future<void> _refreshOne(Dio dio, DiscoveredDevice d) async {
    try {
      final res = await dio.get<Map<String, dynamic>>(
        'http://${d.host}:${d.port}${BIShareApi.info}',
      );
      if (res.statusCode != BIShareStatus.ok || res.data == null) {
        _registerMiss(d.fingerprint);
        return;
      }
      final info = DeviceInfo.fromJson(res.data!);
      // The IP came back as us (address reused): drop the entry.
      if (info.fingerprint == _identity.fingerprint) {
        if (_devices.remove(d.fingerprint) != null) _emit();
        return;
      }
      final host = (info.ip != null && _isUsableIPv4(info.ip!))
          ? info.ip!
          : d.host;
      // Re-key under the canonical HTTP fingerprint (absorbs any TXT/HTTP drift)
      // and refresh alias + lastSeen in place.
      _devices.remove(d.fingerprint);
      _misses.remove(info.fingerprint);
      _devices[info.fingerprint] = DiscoveredDevice(
        fingerprint: info.fingerprint,
        alias: info.alias.isNotEmpty ? info.alias : info.fingerprint,
        host: host,
        port: info.port,
        lastSeen: DateTime.now(),
        deviceModel: info.deviceModel ?? d.deviceModel,
        deviceType: info.deviceType ?? d.deviceType,
        version: info.version,
        quicPort: d.quicPort,
      );
      _dedupeByHost(info.fingerprint, host);
      _emit();
    } on Object {
      _registerMiss(d.fingerprint);
    }
  }

  void _registerMiss(String fingerprint) {
    final n = (_misses[fingerprint] ?? 0) + 1;
    if (n >= _maxMisses) {
      _misses.remove(fingerprint);
      if (_devices.remove(fingerprint) != null) _emit();
    } else {
      _misses[fingerprint] = n;
    }
  }

  void _sweepStale() {
    final now = DateTime.now();
    final cutoff = BIShareConfig.staleDeviceTimeout * 2;
    final before = _devices.length;
    _devices.removeWhere((_, d) => now.difference(d.lastSeen) > cutoff);
    if (_devices.length != before) _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(current);
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
