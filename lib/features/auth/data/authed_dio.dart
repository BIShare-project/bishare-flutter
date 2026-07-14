import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/constants/cloud.dart';
import 'auth_service.dart';
import 'token_store.dart';

/// The authenticated HTTP client for every signed-in request (Fase B / Drive
/// uses this). It:
///  1. attaches `Authorization: Bearer <access>` from the [TokenStore],
///  2. on a `401`, silently refreshes ONCE (single-flight across concurrent
///     requests) then retries the original request, and
///  3. if the refresh fails, clears the session and broadcasts [sessionExpired]
///     so [AuthCubit] can drop to the unauthenticated state.
///
/// Consumers read [dio]. Never point auth endpoints at this client — refresh
/// runs on [AuthService]'s own bare Dio, so there is no interceptor recursion.
class AuthedDio {
  AuthedDio(this._tokens, this._auth) {
    dio = Dio(
      BaseOptions(
        baseUrl: CloudConfig.apiBase,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final TokenStore _tokens;
  final AuthService _auth;

  /// The configured client for authenticated calls.
  late final Dio dio;

  final StreamController<void> _sessionExpired =
      StreamController<void>.broadcast();

  /// Fires once when a refresh fails and the session has been cleared. Listen to
  /// transition the app to the unauthenticated state.
  Stream<void> get sessionExpired => _sessionExpired.stream;

  /// Marks a request that has already been retried, so a second 401 can't loop.
  static const _retriedKey = '__bishare_authed_retried__';

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokens.accessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    final alreadyRetried = err.requestOptions.extra[_retriedKey] == true;
    // Only a fresh 401 with a refresh token on hand is recoverable.
    if (status != 401 || alreadyRetried) return handler.next(err);

    final refreshed = await _refresh();
    if (!refreshed) {
      // Unrecoverable — wipe the session and let the app react.
      await _tokens.clear();
      if (!_sessionExpired.isClosed) _sessionExpired.add(null);
      return handler.next(err);
    }

    // Retry once. Re-running the request re-enters [_onRequest], which attaches
    // the freshly-rotated access token automatically.
    try {
      final options = err.requestOptions..extra[_retriedKey] = true;
      final response = await dio.fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    }
  }

  /// Single-flight refresh: concurrent 401s share one network call.
  Future<bool>? _inflight;

  Future<bool> _refresh() =>
      _inflight ??= _doRefresh().whenComplete(() => _inflight = null);

  Future<bool> _doRefresh() async {
    final refreshToken = await _tokens.refreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final result = await _auth.refresh(refreshToken);
      if (result.accessToken.isEmpty) return false;
      await _tokens.saveAccessToken(result.accessToken);
      // Persist the rotated refresh token ONLY when the server returned one
      // (per §B: absent unless past half-life; the old one stays valid).
      if (result.refreshToken != null && result.refreshToken!.isNotEmpty) {
        await _tokens.saveRefreshToken(result.refreshToken!);
      }
      return true;
    } on Object {
      return false;
    }
  }
}
