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
