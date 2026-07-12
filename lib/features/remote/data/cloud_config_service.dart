import 'package:dio/dio.dart';

import '../../../core/constants/cloud.dart';

/// Backend-enforced transfer limits, fetched once per app run from
/// `GET /api/v1/config` (`data.limits.*`). The app has no login yet, so every
/// user is effectively FREE tier — [freeTransferLimit] is the one to enforce.
///
/// Any failure (offline, timeout, unexpected shape) falls back to the known
/// backend defaults so the share flow never blocks on this fetch. Only a
/// successful fetch is cached; a failed one retries on the next call.
class CloudConfigService {
  /// FREE-tier max transfer size enforced by the backend: 1 GiB.
  static const int defaultFreeTransferLimit = 1073741824;

  /// PRO-tier max transfer size (used in upsell copy): 5 GiB.
  static const int defaultProTransferLimit = 5368709120;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
    ),
  );

  ({int free, int pro})? _cached;
  Future<({int free, int pro})>? _inflight;

  /// The FREE-tier max transfer size in bytes. Never throws.
  Future<int> freeTransferLimit() async => (await _limits()).free;

  /// The PRO-tier max transfer size in bytes. Never throws.
  Future<int> proTransferLimit() async => (await _limits()).pro;

  Future<({int free, int pro})> _limits() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<({int free, int pro})> _fetch() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${CloudConfig.apiBase}${CloudConfig.config}',
      );
      final data = res.data?['data'];
      final limits = data is Map<String, dynamic> ? data['limits'] : null;
      if (limits is Map<String, dynamic>) {
        final free = (limits['transfer_max_file_size_free'] as num?)?.toInt();
        final pro = (limits['transfer_max_file_size_pro'] as num?)?.toInt();
        if (free != null && free > 0) {
          return _cached = (
            free: free,
            pro: (pro != null && pro > 0) ? pro : defaultProTransferLimit,
          );
        }
      }
    } on Object catch (_) {
      // Fall through to the defaults below.
    }
    return (free: defaultFreeTransferLimit, pro: defaultProTransferLimit);
  }
}
