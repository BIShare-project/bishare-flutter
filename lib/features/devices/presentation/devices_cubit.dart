import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/devices/device_registry.dart';
import '../../../core/storage/app_database.dart';
import '../../history/data/history_repository.dart';

/// How the Devices roster is ordered.
enum DeviceSort {
  onlineFirst,
  lastSeen,
  name;

  String get label => switch (this) {
    DeviceSort.onlineFirst => 'devices.sort_online_first'.tr(),
    DeviceSort.lastSeen => 'devices.sort_last_seen'.tr(),
    DeviceSort.name => 'devices.sort_name'.tr(),
  };
}

/// Aggregate transfer statistics with one peer (history rows matched by
/// fingerprint), shown in the device detail sheet.
class DeviceTransferStats extends Equatable {
  const DeviceTransferStats({
    this.sentCount = 0,
    this.sentBytes = 0,
    this.receivedCount = 0,
    this.receivedBytes = 0,
    this.lastTransfer,
  });

  final int sentCount;
  final int sentBytes;
  final int receivedCount;
  final int receivedBytes;

  /// The most recent transfer (either direction) with this peer.
  final TransferRecord? lastTransfer;

  bool get isEmpty => sentCount == 0 && receivedCount == 0;

  @override
  List<Object?> get props => [
    sentCount,
    sentBytes,
    receivedCount,
    receivedBytes,
    lastTransfer,
  ];
}

class DevicesState extends Equatable {
  const DevicesState({
    this.all = const [],
    this.query = '',
    this.sort = DeviceSort.onlineFirst,
  });

  /// The merged roster as emitted by [PresenceDeviceRegistry] (already
  /// online-first + most-recently-seen).
  final List<KnownDeviceView> all;
  final String query;
  final DeviceSort sort;

  /// The roster after the search query and the active sort.
  List<KnownDeviceView> get filtered {
    final q = query.trim().toLowerCase();
    final list = all
        .where(
          (d) =>
              q.isEmpty ||
              d.displayName.toLowerCase().contains(q) ||
              d.alias.toLowerCase().contains(q) ||
              (d.deviceModel?.toLowerCase().contains(q) ?? false) ||
              (d.lastIp?.contains(q) ?? false),
        )
        .toList();
    switch (sort) {
      case DeviceSort.onlineFirst:
        // The registry already emits online-first + lastSeen desc; re-sort so
        // the order also holds for snapshots built in tests or after filtering.
        list.sort((a, b) {
          if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
          return b.lastSeen.compareTo(a.lastSeen);
        });
      case DeviceSort.lastSeen:
        list.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      case DeviceSort.name:
        list.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
    }
    return List.unmodifiable(list);
  }

  /// The "Online now" section (order follows [filtered]).
  List<KnownDeviceView> get onlineNow =>
      filtered.where((d) => d.isOnline).toList(growable: false);

  /// The "Known devices" section: remembered peers not visible right now.
  List<KnownDeviceView> get knownOffline =>
      filtered.where((d) => !d.isOnline).toList(growable: false);

  DevicesState copyWith({
    List<KnownDeviceView>? all,
    String? query,
    DeviceSort? sort,
  }) => DevicesState(
    all: all ?? this.all,
    query: query ?? this.query,
    sort: sort ?? this.sort,
  );

  @override
  List<Object?> get props => [all, query, sort];
}

/// Drives the Devices dashboard over the unified roster stream
/// ([PresenceDeviceRegistry]), with search + sort, per-peer transfer stats,
/// and the roster remove action.
class DevicesCubit extends Cubit<DevicesState> {
  DevicesCubit(
    PresenceDeviceRegistry registry,
    HistoryRepository history,
    AppDatabase db,
  ) : this.fromStream(registry.devices, registry.current, history, db);

  /// Test seam: the same cubit over a raw roster stream + initial snapshot,
  /// so tests don't have to stand up discovery/mDNS.
  @visibleForTesting
  DevicesCubit.fromStream(
    Stream<List<KnownDeviceView>> roster,
    List<KnownDeviceView> initial,
    this._history,
    this._db,
  ) : super(DevicesState(all: initial)) {
    _sub = roster.listen((rows) => emit(state.copyWith(all: rows)));
  }

  final HistoryRepository _history;
  final AppDatabase _db;
  late final StreamSubscription<List<KnownDeviceView>> _sub;

  void setQuery(String q) => emit(state.copyWith(query: q));
  void setSort(DeviceSort s) => emit(state.copyWith(sort: s));

  /// Totals + last transfer with this peer, folded from the history log.
  Future<DeviceTransferStats> statsFor(String fingerprint) async {
    final rows = await _history.watchAll().first; // newest first
    var sentCount = 0, sentBytes = 0, receivedCount = 0, receivedBytes = 0;
    TransferRecord? last;
    for (final r in rows) {
      if (r.deviceFingerprint != fingerprint) continue;
      last ??= r;
      if (r.direction == 'sent') {
        sentCount++;
        sentBytes += r.fileSize;
      } else {
        receivedCount++;
        receivedBytes += r.fileSize;
      }
    }
    return DeviceTransferStats(
      sentCount: sentCount,
      sentBytes: sentBytes,
      receivedCount: receivedCount,
      receivedBytes: receivedBytes,
      lastTransfer: last,
    );
  }

  /// Forget a peer: drop its roster row and its favorite (if any). A device
  /// that is still online reappears on the next discovery sighting.
  Future<void> remove(String fingerprint) async {
    await _db.removeFavorite(fingerprint);
    await _db.deleteKnownDevice(fingerprint);
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
