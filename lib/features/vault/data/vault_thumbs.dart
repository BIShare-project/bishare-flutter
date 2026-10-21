import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../core/rust/rust_facade.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/vault_tables.dart';
import 'vault_api.dart';
import 'vault_keys.dart';
import 'vault_meta.dart';

/// Thumbnails of photos and videos (drive-plan.md task 4.6, VAULT-SPEC
/// "Thumbnails"): made on the device that uploads, at most 32 KB of JPEG,
/// sealed with a key derived from the file's own key and bound to its object,
/// so the server stores a picture it cannot see. Other devices fetch them in
/// batches, open them with the file key from the sealed metadata, and keep
/// them in the cache folder (the system may clear it; they come back).
class VaultThumbs {
  VaultThumbs({
    required VaultApi api,
    required VaultKeyStore keys,
    required VaultDao dao,
    Dio? http,
    Future<Directory> Function()? cacheDir,
  }) : _api = api,
       _keys = keys,
       _dao = dao,
       _http =
           http ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               responseType: ResponseType.bytes,
             ),
           ),
       _cacheDir = cacheDir ?? _defaultCacheDir;

  final VaultApi _api;
  final VaultKeyStore _keys;
  final VaultDao _dao;
  final Dio _http;
  final Future<Directory> Function() _cacheDir;

  /// The server's limit for the JPEG inside a sealed thumbnail.
  static const maxJpeg = 32 * 1024;
  static const _edge = 320;

  static Future<Directory> _defaultCacheDir() async {
    final dir = Directory(
      '${(await getApplicationCacheDirectory()).path}/vault-thumbs',
    );
    await dir.create(recursive: true);
    return dir;
  }

  static bool wants(String? mime) =>
      mime != null && (mime.startsWith('image/') || mime.startsWith('video/'));

  // ---- making one ------------------------------------------------------------------

  /// A JPEG thumbnail of the photo or video at [source], at most [maxJpeg]
  /// bytes, or null when the type has no picture this device can make.
  static Future<Uint8List?> make(File source, String mime) async {
    try {
      if (mime.startsWith('video/')) {
        if (!(Platform.isAndroid || Platform.isIOS)) return null;
        final frame = await VideoThumbnail.thumbnailData(
          video: source.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: _edge,
          quality: 70,
        );
        if (frame == null) return null;
        return frame.length <= maxJpeg
            ? frame
            : await compute(_shrink, (bytes: frame, edge: _edge));
      }
      if (!mime.startsWith('image/')) return null;
      final bytes = await source.readAsBytes();
      final made = await compute(_shrink, (bytes: bytes, edge: _edge));
      if (made != null) return made;
      // HEIC, AVIF and the like: the image package cannot read them, the
      // platform's own decoder (through the engine) often can.
      return await _viaEngine(bytes);
    } on Object catch (e) {
      debugPrint('[vault] thumbnail of ${source.path}: $e');
      return null;
    }
  }

  static Future<Uint8List?> _viaEngine(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: _edge);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final rgba = await image.toByteData();
    final w = image.width, h = image.height;
    image.dispose();
    codec.dispose();
    if (rgba == null) return null;
    return compute(_encodeRgba, (
      rgba: rgba.buffer.asUint8List(),
      width: w,
      height: h,
    ));
  }

  /// Seal [jpeg] for object [objectId] with its [fileKey] and store it.
  Future<void> upload(
    String vaultId,
    String objectId,
    Uint8List fileKey,
    Uint8List jpeg,
  ) async {
    final sealed = Rust.vaultSealThumbnail(
      fileKey: fileKey,
      vaultId: vaultId,
      objectId: objectId,
      jpeg: jpeg,
    );
    await _api.putThumb(vaultId, objectId, sealed);
    _mem[objectId] = jpeg;
    try {
      await File(
        '${(await _cacheDir()).path}/$objectId.jpg',
      ).writeAsBytes(jpeg);
    } on Object {
      // The cache is a convenience.
    }
  }

  // ---- showing them ------------------------------------------------------------------

  final Map<String, Uint8List?> _mem = {};
  final Map<String, Completer<Uint8List?>> _waiting = {};
  final List<String> _batch = [];
  Timer? _flushTimer;

  /// The thumbnail of [o], from memory, the cache folder or the server.
  /// Calls made within a few milliseconds are fetched in one request.
  Future<Uint8List?> load(VaultObject o) async {
    if (!o.hasThumb || o.kind != 'file') return null;
    if (_mem.containsKey(o.id)) return _mem[o.id];
    final pending = _waiting[o.id];
    if (pending != null) return pending.future;
    final c = Completer<Uint8List?>();
    _waiting[o.id] = c;
    Uint8List? cached;
    try {
      final f = File('${(await _cacheDir()).path}/${o.id}.jpg');
      if (await f.exists()) cached = await f.readAsBytes();
    } on Object {
      // Fetch it instead.
    }
    if (cached != null) {
      _done(o.id, cached);
      return cached;
    }
    _batch.add(o.id);
    _flushTimer ??= Timer(const Duration(milliseconds: 40), _flush);
    return c.future;
  }

  void _done(String id, Uint8List? bytes) {
    if (_mem.length > 400) _mem.remove(_mem.keys.first);
    _mem[id] = bytes;
    _waiting.remove(id)?.complete(bytes);
  }

  Future<void> _flush() async {
    _flushTimer = null;
    final ids = _batch.take(100).toList();
    _batch.removeRange(0, ids.length);
    if (_batch.isNotEmpty) _flushTimer = Timer(Duration.zero, _flush);
    final vaultId = await _keys.vaultId();
    final vk = await _keys.vaultKey();
    if (vaultId == null || vk == null) {
      for (final id in ids) {
        _done(id, null);
      }
      return;
    }
    List<VaultDownload> items;
    try {
      items = await _api.downloads(vaultId, ids, thumbs: true, blobs: false);
    } on Object catch (e) {
      debugPrint('[vault] thumbnails: $e');
      for (final id in ids) {
        // Not cached as missing: the next screen asks again.
        _waiting.remove(id)?.complete(null);
      }
      return;
    }
    final dir = await _cacheDir();
    final byId = {for (final i in items) i.objectId: i};
    // A few at a time: a folder of photos should not open 100 connections.
    for (var i = 0; i < ids.length; i += 6) {
      await Future.wait([
        for (final id in ids.skip(i).take(6))
          _fetchOne(vaultId, vk, id, byId[id], dir),
      ]);
    }
  }

  Future<void> _fetchOne(
    String vaultId,
    Uint8List vk,
    String id,
    VaultDownload? item,
    Directory dir,
  ) async {
    final url = item?.thumbUrl;
    final obj = await _dao.object(id);
    if (url == null || obj == null) return _done(id, null);
    try {
      final res = await _http.get<List<int>>(url);
      final meta = VaultMetaCodec.open(vk, vaultId, id, obj.encMeta);
      final jpeg = Rust.vaultOpenThumbnail(
        fileKey: meta.fileKey!,
        vaultId: vaultId,
        objectId: id,
        sealed: res.data ?? const [],
      );
      _done(id, jpeg);
      await File('${dir.path}/$id.jpg').writeAsBytes(jpeg);
    } on Object catch (e) {
      debugPrint('[vault] thumbnail $id: $e');
      _waiting.remove(id)?.complete(null);
    }
  }

  /// Sign-out: nothing of the old account's pictures stays.
  Future<void> clear() async {
    _mem.clear();
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } on Object {
      // Cache.
    }
  }
}

/// Resize to [edge] on the long side and encode as JPEG small enough for
/// the server; null when the bytes are not an image this package reads.
Uint8List? _shrink(({Uint8List bytes, int edge}) job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;
  return _fit(img.bakeOrientation(decoded), job.edge);
}

Uint8List? _encodeRgba(({Uint8List rgba, int width, int height}) job) {
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    numChannels: 4,
  );
  return _fit(image, 320);
}

Uint8List? _fit(img.Image image, int edge) {
  var size = edge;
  for (final quality in [72, 60, 48, 36]) {
    final long = image.width > image.height ? image.width : image.height;
    final scaled = long > size
        ? (image.width >= image.height
              ? img.copyResize(image, width: size)
              : img.copyResize(image, height: size))
        : image;
    final out = img.encodeJpg(scaled, quality: quality);
    if (out.length <= VaultThumbs.maxJpeg) return out;
    if (quality == 48) size = (edge * 0.75).round();
  }
  return null;
}
