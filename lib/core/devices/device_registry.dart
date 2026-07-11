import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../features/discovery/data/discovery_service.dart';
import '../../features/discovery/domain/discovered_device.dart';
import '../../features/favorites/data/favorites_repository.dart';
import '../storage/app_database.dart';

/// One device in the unified roster: a peer that is either visible right now
/// (discovery) or was seen before (drift `KnownDevices` / favorites), with its
/// presence and favorite state resolved.
class KnownDeviceView extends Equatable {
  const KnownDeviceView({
    required this.fingerprint,
    required this.alias,
    this.deviceModel,
    this.deviceType,
    required this.isOnline,
    required this.lastSeen,
    this.lastIp,
    required this.isFavorite,
    this.customName,
  });

  final String fingerprint;
  final String alias;
  final String? deviceModel;
  final String? deviceType;
  final bool isOnline;
  final DateTime lastSeen;
  final String? lastIp;
  final bool isFavorite;

  /// The user-chosen name (favorites) — display this over [alias] when set.
  final String? customName;

  /// What the UI should call this device: the user-chosen [customName] when
  /// set, otherwise the peer's self-reported [alias].
  String get displayName =>
      (customName != null && customName!.isNotEmpty) ? customName! : alias;

  /// Middle presence tier: no longer discovered but seen within the last
  /// minute (e.g. a phone that just locked its screen).
  bool get isAway =>
      !isOnline &&
      DateTime.now().difference(lastSeen) < const Duration(seconds: 60);

  @override
  List<Object?> get props => [
    fingerprint,
    alias,
    deviceModel,
    deviceType,
    isOnline,
    lastSeen,
    lastIp,
    isFavorite,
    customName,
  ];
}

/// The unified device roster (Devices dashboard foundation).
///
/// Merges three sources into one live [devices] stream: the current discovery
/// list (online), the persistent drift `KnownDevices` roster (offline peers
/// with their last sighting), and favorites (star + custom name — including
/// favorites starred before the roster table existed). Also writes every
/// discovery sighting back to drift (`lastSeen` = now, `lastIp` = host) so
/// "known" survives restarts.
class PresenceDeviceRegistry {
  PresenceDeviceRegistry(this._db, this._discovery, this._favorites) {
    _online = {for (final d in _discovery.current) d.fingerprint: d};
    _discoverySub = _discovery.devices.listen((devices) {
      _online = {for (final d in devices) d.fingerprint: d};
      _emit();
      unawaited(_recordSightings(devices));
    });
    _favoritesSub = _favorites.watch().listen((favs) {
      _favoriteRows = favs;
      _emit();
    });
    _knownSub = _db.watchKnownDevices().listen((rows) {
      _known = {for (final r in rows) r.fingerprint: r};
      _emit();
    });
  }

  final AppDatabase _db;
  final DiscoveryService _discovery;
  final FavoritesRepository _favorites;

  late final StreamSubscription<List<DiscoveredDevice>> _discoverySub;
  late final StreamSubscription<Map<String, FavoriteDevice>> _favoritesSub;
  late final StreamSubscription<List<KnownDevice>> _knownSub;

  Map<String, DiscoveredDevice> _online = {};
  Map<String, FavoriteDevice> _favoriteRows = {};
  Map<String, KnownDevice> _known = {};

  /// Last drift write per fingerprint. Discovery re-emits every few seconds
  /// (keep-alive refresh), so sightings are debounced to at most one row write
  /// per [_writeDebounce] per device.
  final Map<String, DateTime> _lastWrite = {};
  static const _writeDebounce = Duration(seconds: 5);

  final StreamController<List<KnownDeviceView>> _controller =
      StreamController<List<KnownDeviceView>>.broadcast();

  /// Live merged roster: online first, then most recently seen.
  Stream<List<KnownDeviceView>> get devices => _controller.stream;

  /// Synchronous snapshot of the merged roster.
  List<KnownDeviceView> get current => _merge();

  /// Persists a sighting for each discovered peer, debounced per fingerprint.
  Future<void> _recordSightings(List<DiscoveredDevice> devices) async {
    final now = DateTime.now();
    for (final d in devices) {
      final last = _lastWrite[d.fingerprint];
      if (last != null && now.difference(last) < _writeDebounce) continue;
      _lastWrite[d.fingerprint] = now;
      try {
        // Absent columns (capabilities, workspaceId) are left untouched on
        // conflict, so future waves' data survives the sighting writer.
        await _db.upsertKnownDevice(
          KnownDevicesCompanion.insert(
            fingerprint: d.fingerprint,
            alias: d.alias,
            deviceModel: Value(d.deviceModel.isEmpty ? null : d.deviceModel),
            deviceType: Value(d.deviceType),
            lastSeen: now,
            lastIp: Value(d.host),
          ),
        );
      } on Object catch (e) {
        // Best-effort; a failed write is retried on the next debounce window.
        debugPrint('[DeviceRegistry] sighting write failed: $e');
      }
    }
  }

  List<KnownDeviceView> _merge() {
    final fingerprints = <String>{
      ..._known.keys,
      ..._favoriteRows.keys,
      ..._online.keys,
    };

    final views = <KnownDeviceView>[];
    for (final fp in fingerprints) {
      final live = _online[fp];
      final row = _known[fp];
      final fav = _favoriteRows[fp];
      // Live discovery wins for alias/model/ip; the drift row backs offline
      // peers. A favorite with neither (starred before the roster existed)
      // still surfaces, with what favorites stores: name + star date.
      views.add(
        KnownDeviceView(
          fingerprint: fp,
          alias: live?.alias ?? row?.alias ?? fav?.customName ?? fp,
          deviceModel: _nonEmpty(live?.deviceModel) ?? row?.deviceModel,
          deviceType: _nonEmpty(live?.deviceType) ?? row?.deviceType,
          isOnline: live != null,
          lastSeen: live?.lastSeen ?? row?.lastSeen ?? fav!.addedAt,
          lastIp: live?.host ?? row?.lastIp,
          isFavorite: fav != null,
          customName: fav?.customName,
        ),
      );
    }
    views.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return b.lastSeen.compareTo(a.lastSeen);
    });
    return views;
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  void _emit() {
    if (!_controller.isClosed) _controller.add(_merge());
  }

  Future<void> dispose() async {
    await _discoverySub.cancel();
    await _favoritesSub.cancel();
    await _knownSub.cancel();
    await _controller.close();
  }
}
