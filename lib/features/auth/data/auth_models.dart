/// Auth domain models + result types, grounded to §B of the frozen API
/// contract. Plain immutable classes with manual JSON (matching the app's
/// existing DTO style — e.g. `CloudUploadResult`, `ReceivedFile` — rather than
/// pulling freezed codegen in for a single response shape).
library;

/// The authenticated user — mirrors the backend `userResponse` DTO exactly
/// (snake_case keys). `avatar_url` is present only when non-NULL on the server.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.provider,
    required this.tier,
    required this.storageUsed,
    required this.storageLimit,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String name;

  /// `magic` for magic-link accounts; `google` / `apple` for OAuth (deferred).
  final String provider;

  /// `free` | `pro` | … — drives premium gating in Fase B (Drive).
  final String tier;
  final int storageUsed;
  final int storageLimit;
  final String? avatarUrl;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: _str(json['id']),
    email: _str(json['email']),
    name: _str(json['name']),
    provider: _str(json['provider']),
    tier: () {
      final t = _str(json['tier']);
      return t.isEmpty ? 'free' : t;
    }(),
    storageUsed: (json['storage_used'] as num?)?.toInt() ?? 0,
    storageLimit: (json['storage_limit'] as num?)?.toInt() ?? 0,
    // Key omitted entirely when NULL server-side; empty string is a valid value.
    avatarUrl: json.containsKey('avatar_url')
        ? _str(json['avatar_url'])
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'provider': provider,
    'tier': tier,
    'storage_used': storageUsed,
    'storage_limit': storageLimit,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  };

  /// Coerce like the backend's `str()`: non-strings (numbers, null, objects)
  /// become "" rather than throwing.
  static String _str(Object? v) => v is String ? v : '';
}

/// The full auth envelope returned by magic-link verify (and OAuth, later).
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;
}

/// The result of `POST /auth/refresh`. Per §B rotation rule the server returns a
/// new [refreshToken] ONLY when past the token's half-life — otherwise it is
/// null and the old refresh token stays valid (persist the new one only if set).
class RefreshResult {
  const RefreshResult({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;
}

/// A typed auth failure carrying the backend error [code] (e.g. `INVALID_TOKEN`,
/// `VALIDATION_ERROR`, `ACCOUNT_DISABLED`) so the presentation layer can map it
/// to a localized message. [code] is a synthetic `NETWORK` / `UNKNOWN` for
/// transport-level failures with no server envelope.
class AuthException implements Exception {
  const AuthException(this.message, {this.code, this.status});

  final String message;
  final String? code;
  final int? status;

  @override
  String toString() => 'AuthException($code/$status): $message';
}
