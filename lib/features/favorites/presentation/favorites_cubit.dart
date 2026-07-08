import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/storage/app_database.dart';
import '../../discovery/domain/discovered_device.dart';
import '../data/favorites_repository.dart';

/// Reactive favorites (fingerprint → row) for the UI.
class FavoritesCubit extends Cubit<Map<String, FavoriteDevice>> {
  FavoritesCubit(this._repo) : super(const {}) {
    _sub = _repo.watch().listen(emit);
  }

  final FavoritesRepository _repo;
  late final StreamSubscription<Map<String, FavoriteDevice>> _sub;

  bool isFavorite(String fingerprint) => state.containsKey(fingerprint);
  String? customName(String fingerprint) => state[fingerprint]?.customName;
  bool autoAccepts(String fingerprint) =>
      state[fingerprint]?.autoAccept ?? false;

  Future<void> toggle(DiscoveredDevice d) => _repo.toggle(d);
  Future<void> setAutoAccept(String fingerprint, bool v) =>
      _repo.setAutoAccept(fingerprint, v);
  Future<void> setCustomName(String fingerprint, String? name) =>
      _repo.setCustomName(fingerprint, name);

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
