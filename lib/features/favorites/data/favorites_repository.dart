import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../../core/storage/app_database.dart';
import '../../discovery/domain/discovered_device.dart';

/// Trusted peers (drift-backed). Keeps a synchronous cache so the receiver can
/// consult favorites during an incoming prepare (via [isFavorite] /
/// [favoriteAutoAccepts]), and exposes a reactive [watch] for the UI.
class FavoritesRepository {
  FavoritesRepository(this._db) {
    _sub = _db.watchFavorites().listen((rows) {
      _cache = {for (final r in rows) r.fingerprint: r};
    });
  }

  final AppDatabase _db;
  late final StreamSubscription<List<FavoriteDevice>> _sub;
  Map<String, FavoriteDevice> _cache = {};

  Stream<Map<String, FavoriteDevice>> watch() => _db.watchFavorites().map(
    (rows) => {for (final r in rows) r.fingerprint: r},
  );

  bool isFavorite(String fingerprint) => _cache.containsKey(fingerprint);

  bool favoriteAutoAccepts(String fingerprint) =>
      _cache[fingerprint]?.autoAccept ?? false;

  Future<void> toggle(DiscoveredDevice d) async {
    if (_cache.containsKey(d.fingerprint)) {
      await _db.removeFavorite(d.fingerprint);
    } else {
      await _db.upsertFavorite(
        FavoriteDevicesCompanion.insert(
          fingerprint: d.fingerprint,
          addedAt: DateTime.now(),
          customName: Value(d.alias),
        ),
      );
    }
  }

  /// Star/unstar by fingerprint — the Devices dashboard path, which must also
  /// work for remembered peers that are not currently discovered. [name] seeds
  /// the custom name when starring.
  Future<void> toggleFingerprint(String fingerprint, {String? name}) async {
    if (_cache.containsKey(fingerprint)) {
      await _db.removeFavorite(fingerprint);
    } else {
      await _db.upsertFavorite(
        FavoriteDevicesCompanion.insert(
          fingerprint: fingerprint,
          addedAt: DateTime.now(),
          customName: Value(name),
        ),
      );
    }
  }

  /// Rename by fingerprint. The custom name lives on the favorites row, so
  /// renaming a peer that is not a favorite yet stars it.
  Future<void> rename(String fingerprint, String name) async {
    final f = _cache[fingerprint];
    await _db.upsertFavorite(
      FavoriteDevicesCompanion(
        fingerprint: Value(fingerprint),
        customName: Value(name),
        autoAccept: Value(f?.autoAccept ?? false),
        addedAt: Value(f?.addedAt ?? DateTime.now()),
      ),
    );
  }

  /// Set auto-accept by fingerprint. Auto-accept is stored on (and implies)
  /// the trusted favorites row, so enabling it stars the peer first.
  Future<void> setAutoAcceptFingerprint(
    String fingerprint,
    bool value, {
    String? name,
  }) async {
    final f = _cache[fingerprint];
    if (f == null && !value) return;
    await _db.upsertFavorite(
      FavoriteDevicesCompanion(
        fingerprint: Value(fingerprint),
        customName: Value(f?.customName ?? name),
        autoAccept: Value(value),
        addedAt: Value(f?.addedAt ?? DateTime.now()),
      ),
    );
  }

  Future<void> setAutoAccept(String fingerprint, bool value) async {
    final f = _cache[fingerprint];
    if (f == null) return;
    await _db.upsertFavorite(
      FavoriteDevicesCompanion(
        fingerprint: Value(fingerprint),
        customName: Value(f.customName),
        autoAccept: Value(value),
        addedAt: Value(f.addedAt),
      ),
    );
  }

  Future<void> setCustomName(String fingerprint, String? name) async {
    final f = _cache[fingerprint];
    if (f == null) return;
    await _db.upsertFavorite(
      FavoriteDevicesCompanion(
        fingerprint: Value(fingerprint),
        customName: Value(name),
        autoAccept: Value(f.autoAccept),
        addedAt: Value(f.addedAt),
      ),
    );
  }

  Future<void> dispose() => _sub.cancel();
}
