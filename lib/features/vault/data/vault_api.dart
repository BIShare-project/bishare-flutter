import 'dart:convert';
import 'dart:io' show IOException;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

/// One object in a `changes` page: what the server holds about it.
class VaultChange {
  const VaultChange({
    required this.id,
    required this.encMeta,
    required this.blobId,
    required this.size,
    required this.hasThumb,
    required this.seq,
    required this.createdAt,
    required this.trashedAt,
    required this.deleted,
  });

  factory VaultChange.fromJson(Map<String, dynamic> j) => VaultChange(
    id: j['id'] as String,
    encMeta: j['encMeta'] as String?,
    blobId: j['blobId'] as String?,
    size: (j['size'] as num?)?.toInt(),
    hasThumb: j['hasThumb'] == true,
    seq: (j['seq'] as num).toInt(),
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    trashedAt: (j['trashedAt'] as num?)?.toInt(),
    deleted: j['deleted'] == true,
  );

  final String id;

  /// Null for a deleted object (a tombstone).
  final String? encMeta;
  final String? blobId;

  /// Stored (ciphertext) size of the blob.
  final int? size;
  final bool hasThumb;
  final int seq;
  final int createdAt;
  final int? trashedAt;
  final bool deleted;
}

/// One page of `GET changes`.
class VaultChanges {
  const VaultChanges({
    required this.seq,
    required this.resync,
    required this.more,
    required this.objects,
    required this.devices,
  });

  factory VaultChanges.fromJson(Map<String, dynamic> j) => VaultChanges(
    seq: (j['seq'] as num).toInt(),
    resync: j['resync'] == true,
    more: j['more'] == true,
    objects: [
      for (final o in (j['objects'] as List?) ?? const [])
        VaultChange.fromJson(Map<String, dynamic>.from(o as Map)),
    ],
    devices: [
      for (final d in (j['devices'] as List?) ?? const [])
        Map<String, dynamic>.from(d as Map),
    ],
  );

  /// The sequence number to ask from next time.
  final int seq;

  /// The device was so far behind that tombstones are gone: the page starts
  /// over from 0, and the local index must be rebuilt.
  final bool resync;
  final bool more;
  final List<VaultChange> objects;
  final List<Map<String, dynamic>> devices;
}

/// The answer to `POST uploads`: an existing blob with the same content, or
/// where to send the bytes.
class VaultReservation {
  const VaultReservation({
    this.existingBlobId,
    this.uploadId,
    this.blobId,
    this.size = 0,
    this.multipart = false,
    this.partSize = 0,
    this.parts = 1,
    this.url,
    this.partUrls = const {},
  });

  factory VaultReservation.fromJson(Map<String, dynamic> j) {
    final existing = j['existing'];
    if (existing is Map) {
      return VaultReservation(
        existingBlobId: existing['blobId'] as String,
        size: (existing['size'] as num).toInt(),
      );
    }
    return VaultReservation(
      uploadId: j['uploadId'] as String,
      blobId: j['blobId'] as String,
      size: (j['size'] as num).toInt(),
      multipart: j['multipart'] == true,
      partSize: (j['partSize'] as num).toInt(),
      parts: (j['parts'] as num).toInt(),
      url: j['url'] as String?,
      partUrls: _partUrls(j['partUrls']),
    );
  }

  /// Set when the vault already holds these bytes: link to it, send nothing.
  final String? existingBlobId;
  final String? uploadId;
  final String? blobId;
  final int size;
  final bool multipart;
  final int partSize;
  final int parts;

  /// Single upload: the presigned PUT.
  final String? url;

  /// Multipart: presigned PUT per part number (the first ones; ask for more
  /// with [VaultApi.partUrls]).
  final Map<int, String> partUrls;
}

/// One item of `POST downloads`.
class VaultDownload {
  const VaultDownload({
    required this.objectId,
    this.missing = false,
    this.url,
    this.size,
    this.thumbUrl,
    this.retryAfterMs,
  });

  factory VaultDownload.fromJson(Map<String, dynamic> j) => VaultDownload(
    objectId: j['objectId'] as String,
    missing: j['missing'] == true,
    url: j['url'] as String?,
    size: (j['size'] as num?)?.toInt(),
    thumbUrl: j['thumbUrl'] as String?,
    retryAfterMs: (j['retryAfterMs'] as num?)?.toInt(),
  );

  final String objectId;
  final bool missing;
  final String? url;
  final int? size;
  final String? thumbUrl;

  /// Past the read-back allowance the server hands URLs out slowly: ask again
  /// after this long.
  final int? retryAfterMs;
}

/// A Drive file copied out as an ordinary transfer link (task 4.10).
class VaultShare {
  const VaultShare({
    required this.code,
    required this.rawCode,
    required this.expiresAt,
    required this.deleteToken,
  });

  final String code;
  final String rawCode;
  final DateTime expiresAt;
  final String deleteToken;
}

/// A link from Drive as the server lists it (drive-plan.md 6B.3).
class VaultLinkInfo {
  const VaultLinkInfo({
    required this.id,
    required this.encKey,
    required this.kind,
    required this.root,
    required this.objects,
    required this.createdAt,
    required this.expiresAt,
    required this.opens,
  });

  factory VaultLinkInfo.fromJson(Map<String, dynamic> j) {
    DateTime? at(Object? v) => v == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
    return VaultLinkInfo(
      id: j['id'] as String,
      encKey: j['encKey'] as String?,
      kind: j['kind'] as String,
      root: j['root'] as String,
      objects: (j['objects'] as num).toInt(),
      createdAt: at(j['createdAt'])!,
      expiresAt: at(j['expiresAt']),
      opens: (j['opens'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;

  /// The link key sealed with the metadata key; null for a link kept without it.
  final String? encKey;

  /// "file" or "folder".
  final String kind;

  /// The shared file or folder.
  final String root;

  /// Objects it covers: the file, or the folder and its files.
  final int objects;
  final DateTime createdAt;

  /// Null: until it is turned off.
  final DateTime? expiresAt;
  final int opens;
}

Map<int, String> _partUrls(Object? list) => {
  for (final p in (list as List?) ?? const [])
    ((p as Map)['partNumber'] as num).toInt(): p['url'] as String,
};

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

  /// Hand the server what the store gave this device for a Drive plan
  /// (drive-plan.md task 7.2): `{'store': 'apple', 'signedTransaction': jws}`
  /// or `{'store': 'google', 'purchaseToken': token}`. The server checks it
  /// with the store and answers the plan it now has.
  Future<Map<String, dynamic>> entitlement(
    String vaultId,
    Map<String, Object> purchase,
  ) async => Map<String, dynamic>.from(
    await _send(
          'POST',
          '/api/v1/vault/$vaultId/entitlement',
          vaultId: vaultId,
          json: purchase,
        )
        as Map,
  );

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

  /// [provider] and [idToken]: a fresh sign-in, needed only to remove a
  /// device signed in with Apple or Google. This device itself, a browser
  /// or a computer approved by a phone go without one.
  Future<void> removeDevice(
    String vaultId,
    String deviceId, {
    String? provider,
    String? idToken,
  }) => _send(
    'DELETE',
    '/api/v1/vault/$vaultId/devices/$deviceId',
    vaultId: vaultId,
    json: provider == null
        ? const <String, dynamic>{}
        : {'provider': provider, 'idToken': idToken},
  );

  /// [googleTokens]: this Drive's Google Play purchase tokens, so the server
  /// stops the plan from renewing (it keeps only their hashes).
  Future<void> deleteAccount(
    String vaultId, {
    required String provider,
    required String idToken,
    List<String> googleTokens = const [],
  }) => _send(
    'DELETE',
    '/api/v1/vault/$vaultId',
    vaultId: vaultId,
    json: {
      'provider': provider,
      'idToken': idToken,
      if (googleTokens.isNotEmpty) 'googleTokens': googleTokens,
    },
  );

  // ---- pairing (key by QR code, task 3.8) --------------------------------------

  /// Signed, like taking the box: the slot belongs to this device of this
  /// vault, and only the vault's own devices can fill it.
  Future<String> openPairSlot() async {
    final data = await _send(
      'POST',
      '/api/v1/vault/pair',
      json: const <String, dynamic>{},
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

  /// A browser waiting to open the Drive, by the slot of its QR code or by
  /// the code typed from its screen (VAULT-SPEC "Opening the Drive in a
  /// browser"). Signed by this device.
  Future<Map<String, dynamic>> webPairSlot(String vaultId, String slot) async =>
      Map<String, dynamic>.from(
        await _send(
              'GET',
              '/api/v1/vault/web-pair/slots/$slot',
              vaultId: vaultId,
            )
            as Map,
      );

  Future<Map<String, dynamic>> webPairCode(String vaultId, String code) async =>
      Map<String, dynamic>.from(
        await _send(
              'GET',
              '/api/v1/vault/web-pair/codes/$code',
              vaultId: vaultId,
            )
            as Map,
      );

  /// Windows and Linux, which have no sign-in of their own (owner,
  /// 2026-10-22): open a slot as a browser does, flagged as a computer, and
  /// wait there for a device of the Drive to approve this one. Unsigned:
  /// this computer belongs to no vault yet.
  Future<({String slot, String code, int expiresAt})> openDesktopPair({
    required String devicePub,
    required String boxPub,
    required String name,
  }) async {
    final data =
        await _send(
              'POST',
              '/api/v1/vault/web-pair',
              signed: false,
              json: {
                'devicePub': devicePub,
                'boxPub': boxPub,
                'name': name,
                'stay': true,
                'desktop': true,
              },
            )
            as Map<String, dynamic>;
    return (
      slot: data['slot'] as String,
      code: data['code'] as String,
      expiresAt: (data['expiresAt'] as num).toInt(),
    );
  }

  /// The approval's box for this computer's slot, signed with its device key
  /// as the slot's own (BIShare-Vault-Pair). Null while nobody approved.
  Future<({String vaultId, Uint8List box, Uint8List granterPub})?>
  takeDesktopPair(String slot) async {
    final data =
        await _send(
              'GET',
              '/api/v1/vault/web-pair/slots/$slot/box',
              pairSlot: slot,
            )
            as Map<String, dynamic>;
    if (data['ready'] != true) return null;
    return (
      vaultId: data['vaultId'] as String,
      box: _b64u(data['box'] as String),
      granterPub: _b64u(data['granterPub'] as String),
    );
  }

  /// This computer shows another code: the old one can no longer be approved.
  Future<void> cancelDesktopPair(String slot) =>
      _send('DELETE', '/api/v1/vault/web-pair/slots/$slot', pairSlot: slot);

  /// Approve the browser: it becomes a device of the vault, and takes [box].
  Future<void> approveWebPair(
    String vaultId,
    String slot, {
    required String devicePub,
    required String boxPub,
    required Uint8List box,
    required Uint8List granterPub,
    required String encName,
  }) => _send(
    'PUT',
    '/api/v1/vault/web-pair/slots/$slot',
    vaultId: vaultId,
    json: {
      'devicePub': devicePub,
      'boxPub': boxPub,
      'box': _enc(box),
      'granterPub': _enc(granterPub),
      'encName': encName,
    },
  );

  /// Null while the slot is still empty.
  Future<({Uint8List box, Uint8List granterPub, String vaultId})?> takePairSlot(
    String slot,
  ) async {
    final data =
        await _send('GET', '/api/v1/vault/pair/$slot') as Map<String, dynamic>;
    if (data['ready'] != true) return null;
    return (
      box: _b64u(data['box'] as String),
      granterPub: _b64u(data['granterPub'] as String),
      vaultId: data['vaultId'] as String,
    );
  }

  // ---- the index (task 4.3) ----------------------------------------------------

  /// One page of changes after [since]; at most [limit] objects (server cap).
  ///
  /// [full]: the next page of a listing from the start (a new device, or
  /// after "start over"), so the server does not send it back to the start
  /// when old deletions have since been forgotten.
  Future<VaultChanges> changes(
    String vaultId,
    int since, {
    int? limit,
    bool full = false,
  }) async => VaultChanges.fromJson(
    await _send(
          'GET',
          '/api/v1/vault/$vaultId/changes?since=$since'
              '${limit == null ? '' : '&limit=$limit'}'
              '${full ? '&full=1' : ''}',
          vaultId: vaultId,
        )
        as Map<String, dynamic>,
  );

  /// A batch of metadata changes, each with its own `opId` so a repeat does
  /// nothing. Answers the new sequence number and one result per op
  /// (`{ok, opId, seq}` or `{ok: false, code, message}`).
  Future<({int seq, List<Map<String, dynamic>> results})> ops(
    String vaultId,
    List<Map<String, dynamic>> ops,
  ) async {
    final data =
        await _send(
              'POST',
              '/api/v1/vault/$vaultId/ops',
              vaultId: vaultId,
              json: {'ops': ops},
            )
            as Map<String, dynamic>;
    return (
      seq: (data['seq'] as num).toInt(),
      results: [
        for (final r in (data['results'] as List?) ?? const [])
          Map<String, dynamic>.from(r as Map),
      ],
    );
  }

  /// The WebSocket that says when the sequence moves. A WebSocket cannot
  /// carry headers everywhere, so the signature travels as `?auth=` and
  /// covers the bare path with an empty body.
  Future<Uri> wsUri(String vaultId) async {
    final path = '/api/v1/vault/$vaultId/ws';
    final auth = Rust.vaultAuthorization(
      seed: await _keys.deviceSeed(),
      vaultId: vaultId,
      method: 'GET',
      pathAndQuery: path,
      ts: now().millisecondsSinceEpoch ~/ 1000,
      body: Uint8List(0),
    );
    final base = Uri.parse(_dio.options.baseUrl);
    return base.replace(
      scheme: base.scheme == 'http' ? 'ws' : 'wss',
      path: path,
      queryParameters: {'auth': auth},
    );
  }

  // ---- uploads (task 4.4) ----------------------------------------------------------

  /// Reserve quota for [size] stored bytes. With a dedupe [tag] the server may
  /// answer with a blob of this vault that holds the same bytes.
  Future<VaultReservation> reserve(
    String vaultId, {
    required int size,
    String? tag,
  }) async => VaultReservation.fromJson(
    await _send(
          'POST',
          '/api/v1/vault/$vaultId/uploads',
          vaultId: vaultId,
          json: {'size': size, 'tag': ?tag},
        )
        as Map<String, dynamic>,
  );

  /// Fresh presigned part URLs (resume after the first ones ran out or
  /// expired); at most 100 per call.
  Future<Map<int, String>> partUrls(
    String vaultId,
    String uploadId,
    List<int> partNumbers,
  ) async {
    final data =
        await _send(
              'POST',
              '/api/v1/vault/$vaultId/uploads/$uploadId/parts',
              vaultId: vaultId,
              json: {'partNumbers': partNumbers},
            )
            as Map<String, dynamic>;
    return _partUrls(data['partUrls']);
  }

  /// A fresh URL for a single upload whose first one expired.
  Future<String> putUrl(String vaultId, String uploadId) async =>
      ((await _send(
                'POST',
                '/api/v1/vault/$vaultId/uploads/$uploadId/parts',
                vaultId: vaultId,
                json: const <String, dynamic>{},
              )
              as Map<String, dynamic>)['url'])
          as String;

  /// Commit the object. [parts]: every part in order with its ETag
  /// (multipart only). A repeat answers the same commit.
  Future<Map<String, dynamic>> complete(
    String vaultId,
    String uploadId, {
    required String objectId,
    required String encMeta,
    List<({int partNumber, String etag})>? parts,
  }) async =>
      await _send(
            'POST',
            '/api/v1/vault/$vaultId/uploads/$uploadId/complete',
            vaultId: vaultId,
            json: {
              'objectId': objectId,
              'encMeta': encMeta,
              if (parts != null)
                'parts': [
                  for (final p in parts)
                    {'partNumber': p.partNumber, 'etag': p.etag},
                ],
            },
          )
          as Map<String, dynamic>;

  /// Give up an upload and release its reservation.
  Future<void> abort(String vaultId, String uploadId) => _send(
    'DELETE',
    '/api/v1/vault/$vaultId/uploads/$uploadId',
    vaultId: vaultId,
  );

  /// The sealed thumbnail of an object (raw bytes, at most 32 KB of JPEG).
  Future<void> putThumb(String vaultId, String objectId, Uint8List sealed) =>
      _send(
        'PUT',
        '/api/v1/vault/$vaultId/objects/$objectId/thumb',
        vaultId: vaultId,
        raw: sealed,
      );

  // ---- downloads (task 4.5) ----------------------------------------------------------

  /// Short-lived presigned GET URLs for up to 200 objects.
  Future<List<VaultDownload>> downloads(
    String vaultId,
    List<String> objectIds, {
    bool thumbs = false,
    bool blobs = true,
  }) async {
    final data =
        await _send(
              'POST',
              '/api/v1/vault/$vaultId/downloads',
              vaultId: vaultId,
              json: {
                'objectIds': objectIds,
                if (thumbs) 'thumbs': true,
                if (!blobs) 'blobs': false,
              },
            )
            as Map<String, dynamic>;
    return [
      for (final i in (data['items'] as List?) ?? const [])
        VaultDownload.fromJson(Map<String, dynamic>.from(i as Map)),
    ];
  }

  // ---- sharing (task 4.10) ------------------------------------------------------------

  /// Copy one file out as an ordinary transfer link of 6, 12 or 24 hours.
  Future<VaultShare> share(
    String vaultId, {
    required String objectId,
    required String fileName,
    required String mimeType,
    required int expiryHours,
    bool oneTime = false,
    int? mtimeMs,
  }) async {
    final data =
        await _send(
              'POST',
              '/api/v1/vault/$vaultId/shares',
              vaultId: vaultId,
              json: {
                'objectId': objectId,
                'fileName': fileName,
                'mimeType': mimeType,
                'expiryHours': expiryHours,
                if (oneTime) 'oneTime': true,
                'mtimeMs': ?mtimeMs,
              },
            )
            as Map<String, dynamic>;
    return VaultShare(
      code: data['code'] as String,
      rawCode: data['rawCode'] as String,
      expiresAt: DateTime.parse(data['expiresAt'] as String),
      deleteToken: data['deleteToken'] as String,
    );
  }

  // ---- links from Drive (drive-plan.md 6B.3) -----------------------------------------

  /// Make a link: [days] is 1, 7 or 30, or 0 for until it is turned off.
  Future<VaultLinkInfo> createLink(
    String vaultId, {
    required String linkId,
    required String kind,
    required List<String> objectIds,
    required String manifest,
    required String encKey,
    required int days,
  }) async => VaultLinkInfo.fromJson(
    await _send(
          'POST',
          '/api/v1/vault/$vaultId/links',
          vaultId: vaultId,
          json: {
            'linkId': linkId,
            'kind': kind,
            'objectIds': objectIds,
            'manifest': manifest,
            'encKey': encKey,
            'days': days,
          },
        )
        as Map<String, dynamic>,
  );

  /// What a link covers, sent again (a folder that changed); its lifetime stays.
  Future<VaultLinkInfo> updateLink(
    String vaultId,
    String linkId, {
    required String kind,
    required List<String> objectIds,
    required String manifest,
  }) async => VaultLinkInfo.fromJson(
    await _send(
          'PUT',
          '/api/v1/vault/$vaultId/links/$linkId',
          vaultId: vaultId,
          json: {'kind': kind, 'objectIds': objectIds, 'manifest': manifest},
        )
        as Map<String, dynamic>,
  );

  /// The Drive's links that still open, newest first.
  Future<List<VaultLinkInfo>> links(String vaultId) async {
    final data =
        await _send('GET', '/api/v1/vault/$vaultId/links', vaultId: vaultId)
            as Map<String, dynamic>;
    return [
      for (final l in data['links'] as List)
        VaultLinkInfo.fromJson(Map<String, dynamic>.from(l as Map)),
    ];
  }

  Future<void> revokeLink(String vaultId, String linkId) =>
      _send('DELETE', '/api/v1/vault/$vaultId/links/$linkId', vaultId: vaultId);

  /// The link emailed to [to]. [link] is the whole link, key included: the
  /// server takes it only as this link's own address.
  Future<void> emailLink(
    String vaultId,
    String linkId, {
    required String to,
    required String link,
    String? name,
    String? title,
  }) => _send(
    'POST',
    '/api/v1/vault/$vaultId/links/$linkId/email',
    vaultId: vaultId,
    json: {'to': to, 'link': link, 'name': ?name, 'title': ?title},
  );

  // ---- transport ----------------------------------------------------------------

  /// Send one request. [path] includes any query string; it is signed as is.
  Future<Object?> _send(
    String method,
    String path, {
    String? vaultId,
    Map<String, dynamic>? json,
    Uint8List? raw,
    bool signed = true,
    String? pairSlot,
  }) async {
    final body =
        raw ??
        (json == null
            ? Uint8List(0)
            : Uint8List.fromList(utf8.encode(jsonEncode(json))));
    final headers = <String, dynamic>{
      if (json != null) Headers.contentTypeHeader: Headers.jsonContentType,
      if (raw != null) Headers.contentTypeHeader: 'application/octet-stream',
    };
    if (pairSlot != null) {
      // A computer waiting in its pairing slot: no vault yet, the slot instead.
      headers['Authorization'] = Rust.vaultPairAuthorization(
        seed: await _keys.deviceSeed(),
        slot: pairSlot,
        method: method,
        pathAndQuery: path,
        ts: now().millisecondsSinceEpoch ~/ 1000,
        body: body,
      );
    } else if (signed) {
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
    final status = e.response?.statusCode;
    if (status == null || status >= 500) {
      // The cause behind "network error", for logcat.
      debugPrint('[vault] ${e.requestOptions.path}: ${e.type.name} ${e.error}');
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const VaultApiException('NETWORK', 'network error');
      // A socket closed mid-request, or a gateway page from in front of the
      // API (502, 503, 504): the connection, not the request, went wrong.
      case DioExceptionType.unknown when e.error is IOException:
        return const VaultApiException('NETWORK', 'network error');
      case DioExceptionType.badResponse when status != null && status >= 500:
        return VaultApiException('NETWORK', 'server error', status: status);
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
