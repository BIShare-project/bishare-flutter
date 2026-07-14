import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_models.dart';

/// Persists the auth session — access token, refresh token, and the cached user
/// — in the OS secure store (Keychain / Keystore). The single source of truth
/// for "is there a session" and the current [tier]; both [AuthedDio] (Bearer +
/// refresh) and [AuthCubit] (bootstrap + tier) read through it.
class TokenStore {
  TokenStore(this._secure);

  final FlutterSecureStorage _secure;

  static const _kAccess = 'auth_access_token';
  static const _kRefresh = 'auth_refresh_token';
  static const _kUser = 'auth_user';

  AuthUser? _cachedUser;

  Future<String?> accessToken() => _secure.read(key: _kAccess);
  Future<String?> refreshToken() => _secure.read(key: _kRefresh);

  /// Whether a signed-in session exists (an access token is persisted).
  Future<bool> hasSession() async =>
      (await _secure.read(key: _kAccess))?.isNotEmpty ?? false;

  /// The cached user (in-memory first, then secure store). Null when signed out.
  Future<AuthUser?> user() async {
    if (_cachedUser != null) return _cachedUser;
    final raw = await _secure.read(key: _kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        return _cachedUser = AuthUser.fromJson(map);
      }
    } on Object {
      // Corrupt payload — treat as no cached user.
    }
    return null;
  }

  /// The current account tier (`free` when signed out / unknown).
  Future<String> tier() async => (await user())?.tier ?? 'free';

  /// Persist a full session after a successful sign-in.
  Future<void> saveSession(AuthTokens tokens) async {
    _cachedUser = tokens.user;
    await _secure.write(key: _kAccess, value: tokens.accessToken);
    await _secure.write(key: _kRefresh, value: tokens.refreshToken);
    await _secure.write(key: _kUser, value: jsonEncode(tokens.user.toJson()));
  }

  /// Persist a rotated access token after a silent refresh.
  Future<void> saveAccessToken(String token) =>
      _secure.write(key: _kAccess, value: token);

  /// Persist a rotated refresh token (only call when the server returned one).
  Future<void> saveRefreshToken(String token) =>
      _secure.write(key: _kRefresh, value: token);

  /// Replace the cached user (e.g. after a profile refresh in Fase B).
  Future<void> saveUser(AuthUser user) async {
    _cachedUser = user;
    await _secure.write(key: _kUser, value: jsonEncode(user.toJson()));
  }

  /// Wipe the session (sign-out or an unrecoverable refresh failure).
  Future<void> clear() async {
    _cachedUser = null;
    await _secure.delete(key: _kAccess);
    await _secure.delete(key: _kRefresh);
    await _secure.delete(key: _kUser);
  }
}
