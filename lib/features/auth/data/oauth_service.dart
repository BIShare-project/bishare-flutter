import 'dart:io';

import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/constants/cloud.dart';
import '../../../core/identity/device_identity.dart';
import 'auth_models.dart';

/// OAuth client IDs from the Google Cloud Console project. The backend verifies
/// the Google `id_token` against [googleWebClientId] (its `GOOGLE_CLIENT_ID`), so
/// that MUST be the value passed as `serverClientId` — it becomes the token's
/// `aud`. [googleIosClientId] is the native iOS client (its reversed form is the
/// `CFBundleURLTypes` scheme in Info.plist). The Android client is resolved by
/// Play Services from the app's package name + SHA-1 fingerprint, so it never
/// appears in code (only `serverClientId` does).
class OauthConfig {
  OauthConfig._();

  /// Web client — the `serverClientId`; the returned `id_token`'s `aud`.
  static const String googleWebClientId =
      '975128452930-qgpqns0the62g610t3uhvih50670ftof.apps.googleusercontent.com';

  /// iOS native client — passed as `clientId` on iOS + macOS (same bundle id;
  /// reversed → URL scheme).
  static const String googleIosClientId =
      '975128452930-fo7jbcjura24hqt8ammik27ffeie2dbg.apps.googleusercontent.com';
}

/// Talks to the frozen `POST /api/v1/auth/oauth` endpoint (§B) for Google + Apple
/// sign-in. It runs the native provider flow to obtain an `id_token`, then
/// exchanges it for the SAME `{access_token,refresh_token,user}` envelope that
/// magic-link verify returns — so [AuthCubit] persists and emits a session
/// through the exact same path.
///
/// Like [AuthService], it uses its OWN bare [Dio] (no auth interceptor): these
/// calls are unauthenticated and must never recurse through [AuthedDio].
class OauthService {
  OauthService(this._identity)
    : _dio = Dio(
        BaseOptions(
          baseUrl: CloudConfig.apiBase,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );

  final Dio _dio;
  final DeviceIdentity _identity;

  /// `GoogleSignIn.instance.initialize()` must run once before `authenticate()`.
  bool _googleReady = false;

  /// Platforms with a native Google flow (google_sign_in has no Windows/Linux
  /// implementation — the login page hides the button elsewhere).
  static bool get googleAvailable =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// Apple sign-in is native-only here: the backend verifies `aud` against the
  /// app bundle id, which the Android/web (service-id) flow wouldn't match.
  static bool get appleAvailable => Platform.isIOS || Platform.isMacOS;

  /// Run the native Google flow and exchange the `id_token` for a session.
  ///
  /// Returns null when the user cancels (no error is surfaced). Throws
  /// [AuthException] for a configuration/transport/backend failure.
  Future<AuthTokens?> signInWithGoogle() async {
    String? idToken;
    try {
      final google = GoogleSignIn.instance;
      if (!_googleReady) {
        await google.initialize(
          // serverClientId sets the id_token `aud` to the WEB client, which the
          // backend checks. clientId is the native iOS client, shared by macOS
          // (same com.bishare.app bundle id; its reversed form is the
          // CFBundleURLTypes scheme in both Info.plists); Android resolves its
          // client via the package name + SHA-1, so no clientId is passed there.
          serverClientId: OauthConfig.googleWebClientId,
          clientId: Platform.isIOS || Platform.isMacOS
              ? OauthConfig.googleIosClientId
              : null,
        );
        _googleReady = true;
      }
      final account = await google.authenticate(scopeHint: const ['email']);
      idToken = account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      // User dismissed the picker — treat as a silent no-op, not an error.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthException(
        e.description ?? 'Google sign-in failed',
        code: 'OAUTH',
      );
    } on Object catch (e) {
      // MissingPluginException on unsupported desktops, SDK misconfig, etc.
      throw AuthException('$e', code: 'OAUTH');
    }
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException('Missing Google id_token', code: 'OAUTH');
    }
    return _exchange(provider: 'google', idToken: idToken);
  }

  /// Run the native Apple flow and exchange the `id_token` for a session.
  ///
  /// The full name is only returned by Apple on the FIRST sign-in, so it is
  /// forwarded when present (the backend keeps it for new accounts). Returns null
  /// when the user cancels; throws [AuthException] otherwise.
  Future<AuthTokens?> signInWithApple() async {
    AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw AuthException(e.message, code: 'OAUTH');
    } on Object catch (e) {
      throw AuthException('$e', code: 'OAUTH');
    }
    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException('Missing Apple id_token', code: 'OAUTH');
    }
    return _exchange(
      provider: 'apple',
      idToken: idToken,
      // First-login-only name; null on subsequent logins (backend keeps the old).
      name: _composeName(credential.givenName, credential.familyName),
    );
  }

  /// `POST /auth/oauth` — swap a provider `id_token` for the standard auth
  /// envelope, decoded into the SAME [AuthTokens] the magic-link path uses.
  Future<AuthTokens> _exchange({
    required String provider,
    required String idToken,
    String? name,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        CloudConfig.authOauth,
        data: {
          'provider': provider,
          'id_token': idToken,
          if (name != null && name.isNotEmpty) 'name': name,
          if (_identity.alias.isNotEmpty) 'device_name': _identity.alias,
          if (_identity.fingerprint.isNotEmpty)
            'device_id': _identity.fingerprint,
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

  /// Join Apple's given + family name into a single display name, or null when
  /// neither is present (e.g. a repeat login).
  String? _composeName(String? given, String? family) {
    final name = [
      given,
      family,
    ].where((p) => p != null && p.trim().isNotEmpty).map((p) => p!.trim()).join(' ');
    return name.isEmpty ? null : name;
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
