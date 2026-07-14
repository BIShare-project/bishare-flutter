import 'package:dio/dio.dart';

import '../../../core/constants/cloud.dart';
import 'auth_models.dart';

/// Talks to the frozen `/api/v1/auth` endpoints (§B): magic-link request +
/// verify, refresh-token rotation, and logout. Uses its OWN bare [Dio] (no auth
/// interceptor) so a refresh call can never recurse through [AuthedDio].
class AuthService {
  AuthService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: CloudConfig.apiBase,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          // We inspect non-2xx bodies ourselves to surface the error envelope.
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );

  final Dio _dio;

  /// `POST /auth/magic-link` — request a 6-char code be emailed. The server
  /// returns 200 for known and unknown emails alike (no account disclosure).
  Future<void> requestMagicLink(String email) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        CloudConfig.authMagicLink,
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// `POST /auth/magic-link/verify` — exchange the code for a session. [code]
  /// must be the UPPERCASE 6-char string (server does a case-sensitive compare).
  Future<AuthTokens> verifyMagicLink({
    required String email,
    required String code,
    String? deviceName,
    String? deviceId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        CloudConfig.authMagicLinkVerify,
        data: {
          'email': email,
          'code': code,
          if (deviceName != null && deviceName.isNotEmpty)
            'device_name': deviceName,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        },
      );
      final data = _data(res.data);
      return AuthTokens(
        accessToken: data['access_token'] as String? ?? '',
        refreshToken: data['refresh_token'] as String? ?? '',
        user: AuthUser.fromJson(
          (data['user'] as Map<String, dynamic>?) ?? const {},
        ),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// `POST /auth/refresh` — mint a fresh access token. A new refresh token is
  /// returned ONLY when the server rotated (past half-life); [RefreshResult]
  /// carries null otherwise, and the caller keeps the old refresh token.
  Future<RefreshResult> refresh(String refreshToken) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        CloudConfig.authRefresh,
        data: {'refresh_token': refreshToken},
      );
      final data = _data(res.data);
      return RefreshResult(
        accessToken: data['access_token'] as String? ?? '',
        refreshToken: data['refresh_token'] as String?,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// `POST /auth/logout` — best-effort refresh-token revoke (Bearer required).
  /// The access JWT stays valid until exp; this never throws (fire-and-forget).
  Future<void> logout({
    required String accessToken,
    String? refreshToken,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        CloudConfig.authLogout,
        data: {
          if (refreshToken != null && refreshToken.isNotEmpty)
            'refresh_token': refreshToken,
        },
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } on DioException {
      // Logout is best-effort; a network failure still signs the user out
      // locally (the cubit clears the token store regardless).
    }
  }

  /// Unwrap the `{success, data:{…}}` envelope; tolerate a flat body.
  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    if (body == null) return const {};
    final inner = body['data'];
    if (inner is Map<String, dynamic>) return inner;
    return body;
  }

  /// Turn a [DioException] into a typed [AuthException] carrying the backend
  /// error code (for a localized message) or a synthetic transport code.
  AuthException _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return AuthException(
        (err['message'] as String?) ?? '',
        code: err['code'] as String?,
        status: e.response?.statusCode,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const AuthException('network error', code: 'NETWORK');
      default:
        return AuthException(
          e.message ?? 'unknown error',
          code: 'UNKNOWN',
          status: e.response?.statusCode,
        );
    }
  }
}
