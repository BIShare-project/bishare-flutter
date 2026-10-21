import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/cloud.dart';
import '../../../core/rust/rust_facade.dart';
import 'vault_keys.dart';

/// A refused vault request: the server's error code (`VAULT_AUTH`,
/// `STORAGE_LIMIT_EXCEEDED`, …), or `NETWORK` / `UNKNOWN` when no answer came.
class VaultApiException implements Exception {
  const VaultApiException(
    this.code,
    this.message, {
    this.status,
    this.extra = const {},
  });

  final String code;
  final String message;
  final int? status;
  final Map<String, dynamic> extra;

  @override
  String toString() => 'VaultApiException($code, $status): $message';
}

/// The answer to `POST /api/v1/vault/signin`.
class VaultSigninResult {
  const VaultSigninResult({
    required this.vaultId,
    required this.created,
    required this.state,
    required this.plan,
    required this.quotaBytes,
    required this.security,
    required this.keyCheck,
    required this.deviceId,
    required this.deviceStatus,
    required this.serverHalf,
  });

  factory VaultSigninResult.fromJson(Map<String, dynamic> j) =>
      VaultSigninResult(
        vaultId: j['vaultId'] as String,
        created: j['created'] == true,
        state: j['state'] as String? ?? 'free',
        plan: j['plan'] as String? ?? 'free',
        quotaBytes: (j['quotaBytes'] as num?)?.toInt() ?? 0,
        security: j['security'] as String? ?? 'standard',
        keyCheck: j['keyCheck'] as String?,
        deviceId: j['deviceId'] as String,
        deviceStatus: j['deviceStatus'] as String? ?? 'active',
        serverHalf: j['serverHalf'] is String
            ? _b64u(j['serverHalf'] as String)
            : null,
      );

  final String vaultId;
  final bool created;
  final String state;
  final String plan;
  final int quotaBytes;
  final String security;

  /// Null until the first device of the account makes the vault key.
  final String? keyCheck;
  final String deviceId;

  /// "active", or "pending" (Maximum security, waiting for approval).
  final String deviceStatus;

  /// The server half of the key copy; null for a device that may not open the vault.
  final Uint8List? serverHalf;
}

/// The `/api/v1/vault/*` routes (drive-plan.md "Routes"), every one but
/// sign-in signed with this device's key (VAULT-SPEC "Signed requests").
///
/// The signature covers the method, the path and query exactly as sent, the
/// time and the body's SHA-256, so this client builds the path itself and
/// sends the body as the very bytes it signed.
class VaultApi {
  VaultApi(this._keys, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: CloudConfig.apiBase,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              responseType: ResponseType.json,
            ),
          );

  final VaultKeyStore _keys;
  final Dio _dio;

  /// For tests: the clock the `ts` comes from.
  DateTime Function() now = DateTime.now;

  // ---- sign-in (the only unsigned call besides pairing) ----------------------

  Future<VaultSigninResult> signin({
    required String provider,
    required String idToken,
    String? appleCode,
  }) async {
    final pub = await _keys.devicePublicKey();
    final body = {
      'provider': provider,
      'idToken': idToken,
      'devicePublicKey': _enc(pub),
      if (appleCode != null && appleCode.isNotEmpty) 'appleCode': appleCode,
    };
    final data = await _send(
      'POST',
      '/api/v1/vault/signin',
      json: body,
      signed: false,
    );
    return VaultSigninResult.fromJson(data as Map<String, dynamic>);
  }

  // ---- account ---------------------------------------------------------------

  Future<Map<String, dynamic>> info(String vaultId) async =>
      await _send('GET', '/api/v1/vault/$vaultId', vaultId: vaultId)
          as Map<String, dynamic>;

  /// Register the key check of a vault key this device just made. A 409
  /// `VAULT_KEY_EXISTS` means another device was first.
  Future<void> registerKeyCheck(String vaultId, String keyCheck) => _send(
    'POST',
    '/api/v1/vault/$vaultId/key',
    vaultId: vaultId,
    json: {'keyCheck': keyCheck},
  );

  Future<void> linkIdentity(
    String vaultId, {
    required String provider,
    required String idToken,
  }) => _send(
    'POST',
    '/api/v1/vault/$vaultId/identities',
    vaultId: vaultId,
    json: {'provider': provider, 'idToken': idToken},
  );

  /// [provider]/[idToken]: a sign-in from the last ten minutes (any linked one).
  Future<void> unlinkIdentity(
    String vaultId,
    String unlink, {
    required String provider,
    required String idToken,
  }) => _send(
    'DELETE',
    '/api/v1/vault/$vaultId/identities/$unlink',
    vaultId: vaultId,
    json: {'provider': provider, 'idToken': idToken},
  );

  Future<void> removeDevice(
    String vaultId,
    String deviceId, {
    required String provider,
    required String idToken,
  }) => _send(
    'DELETE',
    '/api/v1/vault/$vaultId/devices/$deviceId',
    vaultId: vaultId,
    json: {'provider': provider, 'idToken': idToken},
  );

  Future<void> deleteAccount(
    String vaultId, {
    required String provider,
    required String idToken,
  }) => _send(
    'DELETE',
    '/api/v1/vault/$vaultId',
    vaultId: vaultId,
    json: {'provider': provider, 'idToken': idToken},
  );

  // ---- pairing (key by QR code, task 3.8) --------------------------------------

  Future<String> openPairSlot() async {
    final data = await _send(
      'POST',
      '/api/v1/vault/pair',
      json: const <String, dynamic>{},
      signed: false,
    );
    return (data as Map<String, dynamic>)['slot'] as String;
  }

  Future<void> fillPairSlot(
    String vaultId,
    String slot, {
    required Uint8List box,
    required Uint8List granterPub,
  }) => _send(
    'PUT',
    '/api/v1/vault/pair/$slot',
    vaultId: vaultId,
    json: {'box': _enc(box), 'granterPub': _enc(granterPub)},
  );

  /// Null while the slot is still empty.
  Future<({Uint8List box, Uint8List granterPub, String vaultId})?> takePairSlot(
    String slot,
  ) async {
    final data =
        await _send('GET', '/api/v1/vault/pair/$slot', signed: false)
            as Map<String, dynamic>;
    if (data['ready'] != true) return null;
    return (
      box: _b64u(data['box'] as String),
      granterPub: _b64u(data['granterPub'] as String),
      vaultId: data['vaultId'] as String,
    );
  }

  // ---- transport ----------------------------------------------------------------

  /// Send one request. [path] includes any query string; it is signed as is.
  Future<Object?> _send(
    String method,
    String path, {
    String? vaultId,
    Map<String, dynamic>? json,
    bool signed = true,
  }) async {
    final body = json == null
        ? Uint8List(0)
        : Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final headers = <String, dynamic>{
      if (json != null) Headers.contentTypeHeader: Headers.jsonContentType,
    };
    if (signed) {
      final id = vaultId ?? await _keys.vaultId();
      if (id == null) {
        throw const VaultApiException(
          'VAULT_NOT_SIGNED_IN',
          'No Drive account on this device',
        );
      }
      headers['Authorization'] = Rust.vaultAuthorization(
        seed: await _keys.deviceSeed(),
        vaultId: id,
        method: method,
        pathAndQuery: path,
        ts: now().millisecondsSinceEpoch ~/ 1000,
        body: body,
      );
    }
    try {
      final res = await _dio.request<Object?>(
        path,
        data: body.isEmpty ? null : body,
        options: Options(method: method, headers: headers),
      );
      final data = res.data;
      if (data is Map && data['success'] == true) return data['data'];
      return data;
    } on DioException catch (e) {
      throw _error(e);
    }
  }

  static VaultApiException _error(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = Map<String, dynamic>.from(data['error'] as Map);
      return VaultApiException(
        err['code'] as String? ?? 'UNKNOWN',
        err['message'] as String? ?? '',
        status: e.response?.statusCode,
        extra: err,
      );
    }
    if (e.response?.statusCode == 404) {
      // The flag is off: every vault path answers the plain 404 it always had.
      return const VaultApiException(
        'VAULT_UNAVAILABLE',
        'Drive is not available',
        status: 404,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const VaultApiException('NETWORK', 'network error');
      default:
        return VaultApiException(
          'UNKNOWN',
          e.message ?? 'unknown error',
          status: e.response?.statusCode,
        );
    }
  }
}

String _enc(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64u(String s) => base64Url.decode(base64Url.normalize(s));
