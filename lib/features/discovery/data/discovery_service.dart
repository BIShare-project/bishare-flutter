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
  DiscoveryService(this._identity, {bool advertise = true})
    : _advertise = advertise;

  final DeviceIdentity _identity;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  Timer? _staleTimer;
  Timer? _keepAliveTimer;
  Timer? _netWatchTimer;
  Timer? _retryTimer;
  bool _probing = false;
  bool _refreshing = false;
  bool _restartingForNetwork = false;

  /// Intent flag: a caller wants discovery up. Distinct from `_discovery != null`
  /// (the actual bring-up state) so a failed/partial bring-up can be retried by
  /// the internal supervisor without a caller having to re-invoke [start].
  bool _running = false;

  /// Single-flight queue. Every lifecycle transition (start/stop/restart/
  /// setAdvertising) chains through this, so overlapping triggers — app resume,
  /// rename, visibility toggle, and the internal network-change re-advertise, all
  /// firing unawaited on the one Dart isolate — can never interleave across their
  /// awaits. Interleaving otherwise null-derefs a torn-down broadcast, orphans a
  /// live broadcast that defeats "Hidden", or leaks duplicate periodic timers.
  Future<void> _lifecycle = Future.value();

  /// When the last full /24 sweep started. Rate-limits [probeSubnet] so peer
  /// churn (a flaky peer evicted every few seconds) can't storm the radio with
  /// back-to-back sweeps. Bypassed by `force: true` (network-change path).
  DateTime? _lastSweep;
  static const _sweepCooldown = Duration(seconds: 20);

  /// Whether this device should advertise itself (the "Everyone" vs "Hidden"
  /// visibility intent). Seeded from persisted visibility (see the DI wiring) so
  /// the very first advertisement honors it, and remembered so every [restart]
  /// path — app resume, rename, network-change — keeps honoring it.
  bool _advertise;

  /// The self-IPv4 we last advertised in mDNS. When the device's real IP drifts
  /// away from this (Wi-Fi switch, hotspot on/off, DHCP renew), our TXT record
  /// still points peers at a dead address — so we re-advertise with the fresh IP.
  String? _advertisedIp;

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

  /// Runs [op] after any in-flight lifecycle transition completes. Errors are
  /// isolated so one failed op can't poison the queue for the next.
  Future<void> _serialize(Future<void> Function() op) {
    final next = _lifecycle.then((_) => op());
    _lifecycle = next.catchError((_) {});
    return next;
  }

  /// Starts advertising (if visible) + browsing. Idempotent + serialized.
  Future<void> start() => _serialize(_start);

  /// Stops advertising + browsing and clears the peer list. Serialized.
  Future<void> stop() => _serialize(_stop);

  /// Stop then start as one atomic op — refreshes advertisement (with a freshly
  /// resolved self-IP) + browse. Used on app resume, rename, and network change.
  Future<void> restart() => _serialize(() async {
    await _stop();
    await _start();
  });

  Future<void> _start() async {
    _running = true;
    if (_discovery != null) return; // already up
    try {
      final info = await _identity.makeDeviceInfo();
      _advertisedIp = info.ip;

      // Only broadcast if visibility is "Everyone"; a hidden device still browses.
      // Capture the broadcast in a local: a concurrent teardown that nulls the
      // field can't then turn the post-await use into a null-deref.
      if (_advertise) {
        final broadcast = BonsoirBroadcast(service: _serviceFor(info));
        _broadcast = broadcast;
        await broadcast.initialize();
        await broadcast.start();
      }

      final discovery = BonsoirDiscovery(type: BIShareService.discovery);
      await discovery.initialize();
      final sub = discovery.eventStream?.listen(_onEvent);
      await discovery.start();
      _discovery = discovery;
      _sub = sub;

      _armTimers();

      // mDNS can be blocked (multicast entitlement, VPN, some Wi-Fi APs). If nothing
      // shows up shortly, fall back to a subnet /24 unicast probe.
      Timer(const Duration(seconds: 3), () {
        if (_devices.isEmpty && _discovery != null) unawaited(probeSubnet());
      });
    } on Object catch (e) {
      // Bring-up can throw while an interface is mid-transition (socket bind, iOS
      // local-network entitlement, running in background). Tear the partial state
      // down and schedule a self-healing retry — the retry is what stops a failed
      // start() (e.g. from a network-change restart) stranding discovery forever
      // with its timers cancelled-but-never-rearmed.
      debugPrint('[Discovery] bring-up failed: $e; scheduling retry');
      await _teardownBonsoir();
      if (_running) _scheduleRetry();
    }
  }

  Future<void> _stop() async {
    _running = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _teardownBonsoir();
    _devices.clear();
    _misses.clear();
    _emit();
  }

  /// Cancels timers and tears down the bonsoir broadcast/discovery. Nulls fields
  /// first (so any concurrent read sees a clean "down" state), then awaits the
  /// stops on locals, swallowing stop errors so teardown is always total. Does
  /// NOT touch the peer list — [_stop] owns that.
  Future<void> _teardownBonsoir() async {
    _staleTimer?.cancel();
    _staleTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _netWatchTimer?.cancel();
    _netWatchTimer = null;
    _advertisedIp = null;
    final sub = _sub;
    final discovery = _discovery;
    final broadcast = _broadcast;
    _sub = null;
    _discovery = null;
    _broadcast = null;
    try {
      await sub?.cancel();
    } on Object catch (_) {}
    try {
      await discovery?.stop();
    } on Object catch (_) {}
    try {
      await broadcast?.stop();
    } on Object catch (_) {}
  }

  /// (Re)arms the periodic supervisors. Each field is cancelled before being
  /// overwritten so a stray double-arm can never orphan a timer.
  void _armTimers() {
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sweepStale(),
    );

    // mDNS fires ServiceResolved once and rarely re-announces, so `lastSeen`
    // would never refresh and live peers would be swept as stale. A lightweight
    // keep-alive re-probes each known peer's `/api/v1/info`: it refreshes
    // lastSeen, picks up rename (keyed by the canonical fingerprint), evicts
    // genuinely-dead peers by miss-count, and collapses duplicates by IP.
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshKnown()),
    );

    // Watch for the device's own IP changing out from under us (Wi-Fi switch,
    // hotspot toggle, DHCP renew). Our mDNS TXT still advertises the old IP after
    // such a change, so peers dial a dead address and reconnect/resume fails.
    // No connectivity package is present, so poll the interface list cheaply.
    _netWatchTimer?.cancel();
    _netWatchTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_checkNetworkChange()),
    );
  }

  /// After a failed bring-up, retry once shortly — but only while the intent is
  /// still "running" and we're actually down (a later stop() cancels this).
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (_running && _discovery == null) unawaited(start());
    });
  }

  /// Polled network-change detector. When this device's own LAN IP has drifted
  /// away from what we're advertising, re-advertise with the fresh IP and
  /// actively re-scan the (possibly new) subnet so peers reappear quickly.
  ///
  /// Deliberately ignores the transient "no network" state (`resolve()` returns
  /// loopback while Wi-Fi is mid-handoff) — we wait for a real IP before acting,
  /// otherwise we'd advertise `127.0.0.1` and churn.
  Future<void> _checkNetworkChange() async {
    if (_restartingForNetwork || _discovery == null) return;
    final ip = await LocalIp.resolve();
    if (!_isUsableIPv4(ip)) return; // no usable network yet — hold advertisement
    if (_advertisedIp == null || ip == _advertisedIp) return; // unchanged
    _restartingForNetwork = true;
    final oldIp = _advertisedIp;
    try {
      debugPrint(
        '[Discovery] self-IP changed $oldIp → $ip; re-advertising + re-probing',
      );
      await restart(); // makeDeviceInfo() re-resolves → fresh TXT ip, fresh browse
      await probeSubnet(force: true); // re-find peers on the new subnet now
    } on Object catch (e) {
      debugPrint('[Discovery] network-change restart failed: $e');
    } finally {
      _restartingForNetwork = false;
    }
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
      // Universal-clipboard datagram port (its own UDP port, not quicPort). A
      // 2.4 peer announces clipboard changes here; the value is a fixed
      // constant, so a sender may also target [BISharePort.clipboard] directly.
      'clipPort': '${BISharePort.clipboard}',
    },
  );

  /// Toggle only the mDNS advertisement (browsing continues) — the "Hidden"
  /// visibility setting. Serialized so it can't interleave with a restart.
  Future<void> setAdvertising(bool advertise) =>
      _serialize(() => _setAdvertising(advertise));

  Future<void> _setAdvertising(bool advertise) async {
    _advertise = advertise; // remembered so restart() honors the hidden intent
    if (advertise) {
      if (_broadcast != null || _discovery == null) return;
      try {
        final info = await _identity.makeDeviceInfo();
        _advertisedIp = info.ip;
        final broadcast = BonsoirBroadcast(service: _serviceFor(info));
        _broadcast = broadcast;
        await broadcast.initialize();
        await broadcast.start();
      } on Object catch (e) {
        // Advertising failed to come up (browsing is unaffected). Log and leave
        // the field clean so a later toggle/restart can retry; never let this
        // reject — callers (settings _apply) fire it unawaited.
        debugPrint('[Discovery] setAdvertising failed: $e');
        final broadcast = _broadcast;
        _broadcast = null;
        try {
          await broadcast?.stop();
        } on Object catch (_) {}
      }
    } else {
      final broadcast = _broadcast;
      _broadcast = null;
      try {
        await broadcast?.stop();
      } on Object catch (_) {}
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
    // Assigning to an existing key preserves its LinkedHashMap position (no churn);
    // carry the original `firstSeen` so the peer keeps its stable grid slot.
    _devices[fingerprint] = DiscoveredDevice(
      fingerprint: fingerprint,
      alias: alias,
      host: host,
      port: port,
      lastSeen: DateTime.now(),
      firstSeen: _devices[fingerprint]?.firstSeen ?? DateTime.now(),
      deviceModel: attrs['model'] ?? '',
      deviceType: attrs['deviceType'] ?? 'mobile',
      version: attrs['version'] ?? '2.0',
      // Every BIShare device runs a QUIC server on the fixed [BISharePort.quic];
      // fall back to it when the TXT record omits it so a QUIC-preferred sender
      // isn't silently forced onto TCP.
      quicPort: quicPort ?? BISharePort.quic,
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
  ///
  /// Rate-limited to one sweep per [_sweepCooldown] unless [force] is set — so
  /// peer churn (repeated evictions of a flaky peer) can't storm the radio, while
  /// the network-change path can still force an immediate fresh sweep.
  Future<void> probeSubnet({bool force = false}) async {
    if (_probing) return;
    final now = DateTime.now();
    if (!force &&
        _lastSweep != null &&
        now.difference(_lastSweep!) < _sweepCooldown) {
      return;
    }
    _probing = true;
    _lastSweep = now;
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
      // Network down → resolve() returns loopback; sweeping 127.0.0.x is futile
      // (253 dead requests). Skip until we have a routable address.
      if (!_isUsableIPv4(selfIp)) return;
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
        firstSeen: _devices[info.fingerprint]?.firstSeen ?? DateTime.now(),
        deviceModel: info.deviceModel ?? '',
        deviceType: info.deviceType ?? 'mobile',
        version: info.version,
        // The subnet /api/v1/info probe (used when mDNS is blocked/pending — e.g.
        // a fresh iOS install before the Local Network prompt is granted) carries
        // no QUIC port, so a QUIC-preferred sender was silently falling back to
        // TCP. Every BIShare device runs QUIC on the fixed port — use it.
        quicPort: BISharePort.quic,
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
      // Re-key under the canonical HTTP fingerprint (absorbs any TXT/HTTP drift).
      // When the fingerprint is UNCHANGED (the overwhelmingly common keep-alive
      // case) we must NOT remove-then-re-add: that moves the entry to the end of
      // the LinkedHashMap, churning iteration order and making the home grid jump.
      // Assigning to the existing key updates in place and preserves its position.
      // Only re-key (remove old) when the fingerprint genuinely drifted.
      if (info.fingerprint != d.fingerprint) _devices.remove(d.fingerprint);
      _misses.remove(info.fingerprint);
      _devices[info.fingerprint] = DiscoveredDevice(
        fingerprint: info.fingerprint,
        alias: info.alias.isNotEmpty ? info.alias : info.fingerprint,
        host: host,
        port: info.port,
        lastSeen: DateTime.now(),
        // `firstSeen` is set once and carried forever so the peer never jumps —
        // reuse `d`'s (same physical device even across a fingerprint re-key).
        firstSeen: d.firstSeen,
        deviceModel: info.deviceModel ?? d.deviceModel,
        deviceType: info.deviceType ?? d.deviceType,
        version: info.version,
        // Keep the known QUIC port (from mDNS); the /api/v1/info refresh doesn't
        // carry it, so default to the fixed port rather than dropping to null
        // (which would silently force a QUIC-preferred sender onto TCP).
        quicPort: d.quicPort ?? BISharePort.quic,
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
      // The peer went unreachable at its known IP. It may have moved to a new
      // address on this subnet (DHCP renew / hotspot flip) faster than its mDNS
      // re-announce reaches us — a unicast /24 sweep re-finds it at the new IP.
      // Non-forced, so `probeSubnet`'s cooldown coalesces churn (a flaky peer
      // evicting on a loop) into at most one sweep per window.
      if (_discovery != null) unawaited(probeSubnet());
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
