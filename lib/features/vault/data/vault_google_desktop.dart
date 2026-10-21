import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'google_app_data.dart';
import 'vault_config.dart';
import 'vault_keys.dart';

/// Google sign-in on Windows and Linux (drive-plan.md task 3.4), where
/// google_sign_in has no implementation: the OAuth flow for installed apps,
/// in the person's browser, with PKCE and a redirect to a one-shot server on
/// 127.0.0.1 ("loopback").
///
/// It asks for `openid` and `drive.appdata` only. The ID token goes to the
/// BIShare server as on every other platform (with the device-bound nonce);
/// the Drive tokens stay here, the refresh token in the system's credential
/// store, for the key copy.
///
/// Google requires the desktop client's secret in the token exchange even
/// though an installed app cannot keep it secret. It is not in the source:
/// the release build passes it with
/// `--dart-define=VAULT_GOOGLE_DESKTOP_SECRET=…` from a CI secret. A build
/// without it does not offer Google on the desktop.
class VaultGoogleDesktop implements GoogleDriveAccess {
  VaultGoogleDesktop(this._keys, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final VaultKeyStore _keys;
  final Dio _dio;

  static const _secret = String.fromEnvironment('VAULT_GOOGLE_DESKTOP_SECRET');
  static const _authUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _revokeUrl = 'https://oauth2.googleapis.com/revoke';

  /// How long the browser tab may take before the flow gives up.
  static const _wait = Duration(minutes: 5);

  static bool get available =>
      (Platform.isWindows || Platform.isLinux) && _secret.isNotEmpty;

  String? _access;
  DateTime _accessUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// The browser flow. Returns the ID token, or null when the person closed
  /// the tab or said no. [nonce] binds the token to this device's key.
  Future<String?> signIn(String nonce) async {
    final t = await _authorize(nonce: nonce);
    return t?.idToken;
  }

  @override
  Future<String?> accessToken({bool interactive = false}) async {
    if (_access != null &&
        DateTime.now().isBefore(
          _accessUntil.subtract(const Duration(minutes: 1)),
        )) {
      return _access;
    }
    final refresh = await _keys.googleRefreshToken();
    if (refresh != null) {
      try {
        final res = await _dio.post<Map<String, dynamic>>(
          _tokenUrl,
          data: {
            'client_id': VaultConfig.googleDesktopClientId,
            'client_secret': _secret,
            'refresh_token': refresh,
            'grant_type': 'refresh_token',
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        _keep(res.data ?? const {});
        if (_access != null) return _access;
      } on DioException catch (e) {
        // invalid_grant: the person revoked BIShare in their Google account.
        if (e.response?.statusCode == 400) {
          await _keys.saveGoogleRefreshToken(null);
        }
        debugPrint('[vault] Google refresh failed: ${e.response?.statusCode}');
      }
    }
    if (!interactive) return null;
    final t = await _authorize();
    return t?.accessToken;
  }

  @override
  Future<void> invalidate(String token) async {
    if (token == _access) {
      _access = null;
      _accessUntil = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// Sign-out: revoke the grant at Google and forget the tokens.
  Future<void> forget() async {
    final refresh = await _keys.googleRefreshToken();
    _access = null;
    await _keys.saveGoogleRefreshToken(null);
    if (refresh == null) return;
    try {
      await _dio.post<Object?>(
        _revokeUrl,
        data: {'token': refresh},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException {
      // Already revoked, or offline: the token is gone from this device anyway.
    }
  }

  Future<({String? idToken, String? accessToken})?> _authorize({
    String? nonce,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}';
      final verifier = _random(48);
      final state = _random(24);
      final url = Uri.parse(_authUrl).replace(
        queryParameters: {
          'client_id': VaultConfig.googleDesktopClientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': 'openid ${VaultConfig.driveAppDataScope}',
          'code_challenge': _b64u(sha256.convert(ascii.encode(verifier)).bytes),
          'code_challenge_method': 'S256',
          'state': state,
          'access_type': 'offline',
          'prompt': 'select_account',
          'nonce': ?nonce,
        },
      );
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('no browser to open');
      }
      final code = await _awaitRedirect(
        server,
        state,
      ).timeout(_wait, onTimeout: () => null);
      if (code == null) return null;
      final res = await _dio.post<Map<String, dynamic>>(
        _tokenUrl,
        data: {
          'client_id': VaultConfig.googleDesktopClientId,
          'client_secret': _secret,
          'code': code,
          'code_verifier': verifier,
          'redirect_uri': redirect,
          'grant_type': 'authorization_code',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = res.data ?? const <String, dynamic>{};
      _keep(body);
      final refresh = body['refresh_token'];
      if (refresh is String && refresh.isNotEmpty) {
        await _keys.saveGoogleRefreshToken(refresh);
      }
      return (idToken: body['id_token'] as String?, accessToken: _access);
    } finally {
      await server.close(force: true);
    }
  }

  /// The first request to the loopback server that carries our [state].
  /// Null when the person refused.
  static Future<String?> _awaitRedirect(HttpServer server, String state) async {
    await for (final req in server) {
      final q = req.uri.queryParameters;
      if (q['state'] != state) {
        // A favicon request, or something else knocking on the port.
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        continue;
      }
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_donePage);
      await req.response.close();
      return q['code'];
    }
    return null;
  }

  void _keep(Map<String, dynamic> body) {
    final token = body['access_token'];
    if (token is! String || token.isEmpty) return;
    _access = token;
    final secs = (body['expires_in'] as num?)?.toInt() ?? 3600;
    _accessUntil = DateTime.now().add(Duration(seconds: secs));
  }

  static String _random(int bytes) {
    final rng = Random.secure();
    return _b64u(List<int>.generate(bytes, (_) => rng.nextInt(256)));
  }

  static String _b64u(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  // Shown in the browser tab after Google sends the person back. English
  // only: the tab is closed right away, and the app shows the result.
  static const _donePage =
      '<!doctype html><meta charset="utf-8"><title>BIShare</title>'
      '<body style="font-family:system-ui,sans-serif;text-align:center;'
      'padding:4rem 1rem"><h1 style="font-size:1.4rem">Back to BIShare</h1>'
      '<p>You can close this tab.</p></body>';
}
