import 'package:dio/dio.dart';

import '../../../core/constants/cloud.dart';

/// The backend's transfer size limit, fetched once per app run from
/// `GET /api/v1/config` (`data.limits.transfer_max_file_size_free` — the key
/// keeps its historical name; there is one limit and no tiers).
///
/// Any failure (offline, timeout, unexpected shape) falls back to the known
/// backend default so the share flow never blocks on this fetch. Only a
/// successful fetch is cached; a failed one retries on the next call.
class CloudConfigService {
  /// The backend's default when the flag is unset: 1 GiB.
  static const int defaultTransferLimit = 1073741824;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
    ),
  );

  int? _cached;
  Future<int>? _inflight;

  /// The max transfer size in bytes. Never throws.
  Future<int> transferLimit() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<int> _fetch() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${CloudConfig.apiBase}${CloudConfig.config}',
      );
      final data = res.data?['data'];
      final limits = data is Map<String, dynamic> ? data['limits'] : null;
      if (limits is Map<String, dynamic>) {
        final limit = (limits['transfer_max_file_size_free'] as num?)?.toInt();
        if (limit != null && limit > 0) return _cached = limit;
      }
    } on Object catch (_) {
      // Fall through to the default below.
    }
    return defaultTransferLimit;
  }
}
