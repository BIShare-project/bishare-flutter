import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Access tokens for the one Google Drive scope Drive uses,
/// `drive.appdata` (`VaultConfig.driveAppDataScope`).
///
/// The tokens stay on this device; the BIShare server never sees them
/// (drive-plan.md "Where the key copy lives").
abstract class GoogleDriveAccess {
  /// A token, or null when getting one needs the person and [interactive] is
  /// false (no Google sign-in on this device, or consent not given yet).
  Future<String?> accessToken({bool interactive = false});

  /// Drop a token Google refused, so the next call fetches a fresh one.
  Future<void> invalidate(String token);
}

/// No token without asking the person, and asking was not allowed.
class GoogleAuthNeeded implements Exception {
  const GoogleAuthNeeded();
  @override
  String toString() => 'GoogleAuthNeeded';
}

class GoogleAppDataException implements Exception {
  const GoogleAppDataException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => 'GoogleAppDataException($status): $message';
}

/// Small files in the hidden app-data folder of the person's Google Drive,
/// through the Drive v3 REST API. Only this app can see that folder, and
/// Google deletes it when the person disconnects BIShare from their account.
///
/// Every method needs a token; with [interactive] false and no token at hand
/// it throws [GoogleAuthNeeded] instead of asking the person. Errors from
/// Google throw [GoogleAppDataException].
class GoogleAppData {
  GoogleAppData(this._access, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
            ),
          );

  final GoogleDriveAccess _access;
  final Dio _dio;

  static const _files = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  /// The file's bytes, or null when it is not there.
  Future<Uint8List?> read(String name, {bool interactive = false}) =>
      _withToken(interactive, (token) async {
        final id = await _find(token, name);
        if (id == null) return null;
        final res = await _dio.get<List<int>>(
          '$_files/$id',
          queryParameters: {'alt': 'media'},
          options: _opts(token, responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  /// Create or replace the file.
  Future<void> write(
    String name,
    Uint8List bytes, {
    bool interactive = false,
  }) => _withToken(interactive, (token) async {
    final id = await _find(token, name);
    if (id != null) {
      await _dio.patch<Object?>(
        '$_upload/$id',
        queryParameters: {'uploadType': 'media'},
        data: bytes,
        options: _opts(token, contentType: 'application/octet-stream'),
      );
    } else {
      const boundary = 'bishare-vault-key-copy';
      final meta = jsonEncode({
        'name': name,
        'parents': ['appDataFolder'],
      });
      final body = BytesBuilder(copy: false)
        ..add(
          utf8.encode(
            '--$boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '$meta\r\n'
            '--$boundary\r\n'
            'Content-Type: application/octet-stream\r\n\r\n',
          ),
        )
        ..add(bytes)
        ..add(utf8.encode('\r\n--$boundary--\r\n'));
      await _dio.post<Object?>(
        _upload,
        queryParameters: {'uploadType': 'multipart', 'fields': 'id'},
        data: body.takeBytes(),
        options: _opts(
          token,
          contentType: 'multipart/related; boundary=$boundary',
        ),
      );
    }
  });

  /// Delete the file if it is there.
  Future<void> delete(String name, {bool interactive = false}) =>
      _withToken(interactive, (token) async {
        final id = await _find(token, name);
        if (id != null) {
          await _dio.delete<Object?>('$_files/$id', options: _opts(token));
        }
      });

  Future<String?> _find(String token, String name) async {
    // Names are made by this app ("vault-<base32 id>.key"), so they never
    // contain a quote; refuse anything else rather than escape it.
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
      throw ArgumentError.value(name, 'name');
    }
    final res = await _dio.get<Map<String, dynamic>>(
      _files,
      queryParameters: {
        'spaces': 'appDataFolder',
        'q': "name = '$name' and trashed = false",
        'fields': 'files(id)',
        'pageSize': '10',
      },
      options: _opts(token, responseType: ResponseType.json),
    );
    final files = (res.data?['files'] as List?) ?? const [];
    if (files.isEmpty) return null;
    return (files.first as Map)['id'] as String?;
  }

  /// Run [call] with a token; once more with a fresh token if Google refuses
  /// the first (a revoked or expired token can still be in a cache).
  Future<T> _withToken<T>(
    bool interactive,
    Future<T> Function(String token) call,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final token = await _access.accessToken(interactive: interactive);
      if (token == null) throw const GoogleAuthNeeded();
      try {
        return await call(token);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 401 && attempt == 0) {
          await _access.invalidate(token);
          continue;
        }
        throw GoogleAppDataException(
          e.message ?? 'Google Drive request failed',
          status: status,
        );
      }
    }
  }

  static Options _opts(
    String token, {
    String? contentType,
    ResponseType? responseType,
  }) => Options(
    headers: {'Authorization': 'Bearer $token'},
    contentType: contentType,
    responseType: responseType,
  );
}
