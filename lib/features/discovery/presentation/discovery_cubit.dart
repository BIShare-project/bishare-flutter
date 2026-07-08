import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/discovery_service.dart';
import '../domain/discovered_device.dart';

/// Exposes the live list of nearby peers to the UI.
class DiscoveryCubit extends Cubit<List<DiscoveredDevice>> {
  DiscoveryCubit(this._service) : super(const []) {
    _sub = _service.devices.listen(emit);
    emit(_service.current);
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
