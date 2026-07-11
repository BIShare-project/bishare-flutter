import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/discovery_service.dart';
import '../domain/discovered_device.dart';

/// Exposes the live list of nearby peers to the UI.
///
/// Emits a [stableDeviceOrder]-sorted list so the home grid keeps a device in a
/// fixed slot: discovery insertion order churns every keep-alive, which made
/// devices jump under the user's finger. Sorting once per emit here (O(n log n))
/// keeps the order rock-solid without re-sorting on every widget rebuild.
class DiscoveryCubit extends Cubit<List<DiscoveredDevice>> {
  DiscoveryCubit(this._service) : super(const []) {
    _sub = _service.devices.listen((devices) => emit(stableDeviceOrder(devices)));
    emit(stableDeviceOrder(_service.current));
  }

  final DiscoveryService _service;
  late final StreamSubscription<List<DiscoveredDevice>> _sub;

  Future<void> start() => _service.start();
  Future<void> restart() async {
    await _service.stop();
    await _service.start();
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
