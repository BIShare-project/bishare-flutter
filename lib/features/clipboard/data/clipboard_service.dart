import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../../core/clipboard/clipboard_channel.dart';
import '../../../core/constants/protocol.dart';
import '../../../core/identity/device_identity.dart';
import '../../discovery/data/discovery_service.dart';
import '../../discovery/domain/discovered_device.dart';
import 'clipboard_history_store.dart';
import 'clipboard_relay.dart';
import 'clipboard_token_store.dart';

/// Universal-clipboard sync (opt-in). Text changes are broadcast to discovered
/// peers over UDP :58321 ([BISharePort.clipboard] — its OWN datagram port; the
/// old :58318 collided with the always-on Rust QUIC endpoint and never bound)
/// and incoming clipboards replace the local one.
///
/// v2.4 adds IMAGES over a LAN pull model that emits NO new wire frames
/// (plan §1 / F.1.a): a copied image is staged in [tokenStore] and announced
/// via the SAME UDP `ClipboardPayload` JSON with `kind:'image'`, a one-shot
/// `token`, and an EMPTY `text`. VERIFIED natural fallback: the 2.3 receiver
/// (this file's previous revision) does `if (text.isEmpty) return;` before
/// acting, so the image announce is a provable no-op there. A v2.4 receiver
/// pulls the bytes back with `GET /api/v1/clipboard?token=…` (60s TTL,
/// single-use) and puts them on its own clipboard via the
/// `app.bishare/clipboard` platform channel.
class ClipboardService {
  ClipboardService(this._identity, this._discovery);

  final DeviceIdentity _identity;
  final DiscoveryService _discovery;

  /// Staging area for announced image bytes, shared with `TransferServer`
  /// (which serves the pull route). Wired by the DI layer.
  ClipboardTokenStore? tokenStore;

  /// Ring-buffered history of synced items (drift). Wired by the DI layer.
  ClipboardHistoryStore? history;

  /// Optional cloud path (OFF by default). Wired by the DI layer.
  ClipboardRelay? relay;

  RawDatagramSocket? _socket;
  Timer? _poll;
  String? _lastText;

  /// Echo-loop guard for images (the existing `_lastText` pattern extended to
  /// bytes per plan risk item): the hash of the last image we wrote to or read
  /// from the clipboard — never re-announce it. Set from the READ-BACK bytes
  /// after a write (Apple re-encodes on paste, so the pulled bytes' hash alone
  /// wouldn't match the next poll).
  String? _lastImageHash;

  /// Secondary accepted hash: the ORIGINAL bytes we pulled/re-copied, before the
  /// platform re-encoded them on paste. Either this or [_lastImageHash] suppresses
  /// the next poll — closes the Mac↔iOS ping-pong from pasteboard re-encoding.
  String? _lastImagePulledHash;

  /// Pasteboard generation at the last poll (cheap change gate; null where the
  /// platform can't report one, in which case every poll reads the image).
  int? _lastChangeCount;
  bool _pullingImage = false;
  bool _enabled = false;

  /// Whether the cloud relay path is shippable. OFF: the relay uses a per-device
  /// placeholder channel and the sync backend isn't live, so enabling it would
  /// reconnect forever. Gated here (not just in the UI) so a persisted
  /// `clipboardCloud = true` from an older build can't wake the relay either.
  /// Flip to `true` when the Workers sync backend + account pairing ship.
  static const bool cloudRelayAvailable = false;

  // ---- settings (applied by SettingsCubit) ----
  bool _includeImages = true;
  int _maxImageBytes = 5 * 1024 * 1024;
  bool _cloudSync = false;

  /// Effective cloud state: user opted in AND the backend actually exists.
  bool get _cloudActive => _enabled && _cloudSync && cloudRelayAvailable;

  /// Apply the clipboard sub-settings (Settings → Sync).
  void configure({
    required bool includeImages,
    required int maxImageBytes,
    required bool cloudSync,
  }) {
    _includeImages = includeImages;
    _maxImageBytes = maxImageBytes;
    _cloudSync = cloudSync;
    relay?.setEnabled(_cloudActive);
  }

  /// Called on an incoming text clipboard: (senderAlias, text).
  void Function(String senderAlias, String text)? onReceived;

  /// Called on an incoming image clipboard: (senderAlias).
  void Function(String senderAlias)? onReceivedImage;

  bool get isEnabled => _enabled;

  /// Whether this platform can sync clipboard images at all.
  static bool get imagesSupported => ClipboardImageChannel.isSupported;

  // ---- local re-copy (history "copy again") ----

  /// Prime the echo guards for a TEXT item the user re-copied from history, then
  /// (caller) write it to the system clipboard. Without this, the poll loop sees
  /// the re-copied text as a fresh copy and re-broadcasts + re-records it —
  /// duplicate rows. Set the guard BEFORE the caller writes the clipboard.
  void markLocalCopy(String text) {
    _lastText = text;
  }

  /// Re-copy an IMAGE item from history: writes [bytes] to the clipboard AND
  /// primes the poll's guards (same read-back handling as an incoming pull) so
  /// it isn't re-broadcast/re-recorded. Returns whether the write succeeded.
  /// Routed through the service (not `ClipboardImageChannel` directly) precisely
  /// so the guards are armed around the write.
  Future<bool> markLocalCopyImage(Uint8List bytes, String mime) async {
    _lastImageHash = _hash(bytes); // guard before the write (no-counter platforms)
    _lastImagePulledHash = _hash(bytes);
    final ok = await ClipboardImageChannel.setImage(bytes, mime);
    if (!ok) return false;
    await _primeImageGuardAfterWrite(bytes);
    return true;
  }

  Future<void> setEnabled(bool on) async {
    if (on == _enabled) return;
    if (on) {
      await _start();
    } else {
      _stop();
    }
    relay?.setEnabled(_cloudActive);
  }

  Future<void> _start() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        BISharePort.clipboard,
        reuseAddress: true,
      );
      _socket!
        ..broadcastEnabled = true
        ..listen(_onData);
      // Seed with the current clipboard so we don't broadcast pre-existing
      // content (text, and the pasteboard generation for images).
      _lastText = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      _lastChangeCount = await ClipboardImageChannel.changeCount();
      if (_lastChangeCount == null && _includeImages && imagesSupported) {
        // No generation counter → seed the image hash directly.
        final image = await ClipboardImageChannel.getImage();
        if (image != null) _lastImageHash = _hash(image.bytes);
      }
      _poll = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _pollClipboard(),
      );
      _enabled = true;
      relay?.onPayload = applyRelayPayload;
    } on Object {
      _enabled = false;
      _stop();
    }
  }

  void _stop() {
    _enabled = false;
    _poll?.cancel();
    _poll = null;
    _socket?.close();
    _socket = null;
    tokenStore?.clear(); // nothing staged should outlive the toggle
  }

  Future<void> _pollClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text != null && text.isNotEmpty && text != _lastText) {
      _lastText = text;
      _broadcastText(text);
    }
    await _pollImage();
  }

  // ---- outgoing: text ----

  void _broadcastText(String text) {
    final payload = <String, dynamic>{
      'type': 'clipboard',
      'text': text,
      'sender': _identity.fingerprint,
      'alias': _identity.alias,
    };
    _send(payload, _discovery.current);
    relay?.forward(payload);
    unawaited(
      history?.addText(
        text: text,
        senderAlias: _identity.alias,
        senderFingerprint: _identity.fingerprint,
      ),
    );
  }

  // ---- outgoing: image ----

  Future<void> _pollImage() async {
    if (!_enabled || !_includeImages || !imagesSupported) return;
    // TODO(wave-followup): probe native pasteboard concealed/sensitive types
    // (org.nspasteboard.ConcealedType / Android EXTRA_IS_SENSITIVE) before
    // syncing, so password-manager clips are never broadcast. Needs handlers on
    // all three platforms — deferred.
    // Cheap gate: the pasteboard generation bumps on ANY copy; unchanged →
    // nothing new to read (avoids decoding a many-MB image every 1.5s).
    final count = await ClipboardImageChannel.changeCount();
    if (count != null) {
      if (count == _lastChangeCount) return;
      _lastChangeCount = count;
    }
    final image = await ClipboardImageChannel.getImage();
    if (image == null) return;
    if (image.bytes.length > _maxImageBytes) return; // over the size setting
    final hash = _hash(image.bytes);
    // Echo guard: either the read-back hash (what a re-encoding platform
    // actually hands us) or the original pulled hash suppresses the poll.
    if (hash == _lastImageHash || hash == _lastImagePulledHash) return;
    _lastImageHash = hash;
    _lastImagePulledHash = null;
    await _broadcastImage(image);
  }

  Future<void> _broadcastImage(ClipboardImageData image) async {
    final store = tokenStore;
    if (store == null) return;
    // TODO(wave-followup): encrypt the staged bytes + pull token over the LAN
    // (E2E, like the file-transfer path) so a passive sniffer can't lift a
    // clipboard image or replay its token. Larger change — deferred.
    final preview = await _makePreview(image.bytes);
    final base = <String, dynamic>{
      'type': 'clipboard',
      'text': '', // ← the field a 2.3 receiver checks; empty = proven no-op
      'sender': _identity.fingerprint,
      'alias': _identity.alias,
      'kind': 'image',
      'mime': image.mime,
      'size': image.bytes.length,
      'preview': ?preview,
    };
    // Announce only to peers that can pull (v2.4+). The datagram itself is a
    // natural-fallback shape (no new wire frame, ignored by 2.3 — see class
    // doc), but peers that can't use it shouldn't get megaphone traffic; the
    // UDP path carries no DeviceInfo, so the version gate stands in for
    // PeerCapabilities.canClipboardBinary here (same min-version rule).
    final capable = _discovery.current
        .where(
          (d) => BIShareConfig.versionAtLeast(
            d.version,
            BIShareConfig.clipboardBinaryMinVersion,
          ),
        )
        .toList(growable: false);
    final share = ClipboardShare(bytes: image.bytes, mime: image.mime);
    for (final peer in capable) {
      // Tokens are ONE-SHOT, so each peer gets its own — a second receiver on
      // the LAN isn't starved by the first one's pull.
      _send({...base, 'token': store.publish(share)}, [peer]);
    }
    // Cloud path: small images travel inline (`data`) since a LAN pull token
    // is meaningless across networks. Only encode when it can actually go out
    // (relay on + under the 1 MB payload cap incl. base64's 4/3 expansion) —
    // don't build a multi-MB base64 string just to drop it.
    final cloud = relay;
    if (cloud != null &&
        cloud.isEnabled &&
        image.bytes.length <= (ClipboardRelay.maxPayloadBytes ~/ 4) * 3 -
            16 * 1024) {
      cloud.forward({...base, 'data': base64Encode(image.bytes)});
    }
    unawaited(
      history?.addImage(
        bytes: image.bytes,
        mime: image.mime,
        senderAlias: _identity.alias,
        senderFingerprint: _identity.fingerprint,
      ),
    );
  }

  void _send(Map<String, dynamic> payload, List<DiscoveredDevice> peers) {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(jsonEncode(payload));
    for (final d in peers) {
      try {
        socket.send(data, InternetAddress(d.host), BISharePort.clipboard);
      } on Object {
        // unreachable host — skip
      }
    }
  }

  // ---- incoming (UDP) ----

  void _onData(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    try {
      final map = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (map['type'] != 'clipboard') return;
      if (map['sender'] == _identity.fingerprint) return; // ignore our own
      if (map['kind'] == 'image') {
        unawaited(_pullImage(map));
        return;
      }
      final text = map['text'] as String? ?? '';
      if (text.isEmpty) return;
      _applyText(text, map['alias'] as String? ?? 'A device',
          map['sender'] as String?);
    } on Object {
      // malformed datagram — ignore
    }
  }

  void _applyText(String text, String alias, String? fingerprint) {
    _lastText = text; // don't echo it straight back
    Clipboard.setData(ClipboardData(text: text));
    unawaited(
      history?.addText(
        text: text,
        senderAlias: alias,
        senderFingerprint: fingerprint,
      ),
    );
    onReceived?.call(alias, text);
  }

  /// Pull an announced image over HTTP and put it on the local clipboard.
  ///
  /// Anti-spoof: the announce's `sender` fingerprint MUST match a currently
  /// discovered peer, and the pull targets ONLY that peer's `host` — a forged
  /// datagram from an unknown source is dropped (no `sourceAddress` fallback,
  /// which an attacker on the LAN could otherwise use to feed us its image).
  Future<void> _pullImage(Map<String, dynamic> map) async {
    if (!_enabled || !_includeImages || !imagesSupported) return;
    if (_pullingImage) return; // one pull at a time; a newer copy re-announces
    final token = map['token'] as String?;
    if (token == null || token.isEmpty) return;
    final size = map['size'] as int? ?? 0;
    if (size <= 0 || size > _maxImageBytes) return;
    final sender = map['sender'] as String?;
    final alias = map['alias'] as String? ?? 'A device';
    final mime = map['mime'] as String? ?? 'image/png';
    DiscoveredDevice? peer;
    for (final d in _discovery.current) {
      if (d.fingerprint == sender) {
        peer = d;
        break;
      }
    }
    if (peer == null) return; // unknown/spoofed sender — never pull.
    final host = peer.host;
    final port = peer.port;
    _pullingImage = true;
    // Stream the body so an attacker-declared `size` can't force us to buffer a
    // multi-GB response: reject on an over-cap Content-Length up front, and abort
    // mid-stream the moment the running byte count exceeds the cap.
    final cancel = CancelToken();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.stream,
      ),
    );
    try {
      final res = await dio.get<ResponseBody>(
        'http://$host:$port${BIShareApi.clipboard}',
        queryParameters: {'token': token},
        cancelToken: cancel,
      );
      final declared = int.tryParse(
        res.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declared != null && declared > _maxImageBytes) {
        cancel.cancel();
        return;
      }
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in res.data!.stream) {
        received += chunk.length;
        if (received > _maxImageBytes) {
          cancel.cancel(); // abort the transfer — never hold more than the cap
          return;
        }
        builder.add(chunk);
      }
      if (received == 0 || received != size) return; // must match the announce
      await _applyImage(builder.takeBytes(), mime, alias, sender);
    } on Object catch (e) {
      debugPrint('[Clipboard] image pull failed: $e');
    } finally {
      dio.close(force: true);
      _pullingImage = false;
    }
  }

  Future<void> _applyImage(
    Uint8List bytes,
    String mime,
    String alias,
    String? fingerprint,
  ) async {
    _lastImageHash = _hash(bytes); // set BEFORE writing → poll won't echo
    final ok = await ClipboardImageChannel.setImage(bytes, mime);
    if (!ok) return;
    await _primeImageGuardAfterWrite(bytes);
    unawaited(
      history?.addImage(
        bytes: bytes,
        mime: mime,
        senderAlias: alias,
        senderFingerprint: fingerprint,
      ),
    );
    onReceivedImage?.call(alias);
  }

  /// After WE put [pulledBytes] on the clipboard, re-arm the poll's change gates
  /// so it doesn't treat our own write as a fresh copy and echo it back:
  ///  * refresh [_lastChangeCount] to the post-write generation, and
  ///  * derive [_lastImageHash] from the READ-BACK bytes — Apple platforms
  ///    re-encode on paste (TIFF↔PNG, multi-flavor `writeObjects`), so the bytes
  ///    `getImage()` returns differ from what we wrote. [pulledBytes]' own hash
  ///    is kept as the secondary accepted value ([_lastImagePulledHash]).
  Future<void> _primeImageGuardAfterWrite(Uint8List pulledBytes) async {
    _lastChangeCount = await ClipboardImageChannel.changeCount();
    final readBack = await ClipboardImageChannel.getImage();
    _lastImageHash = readBack != null ? _hash(readBack.bytes) : _hash(pulledBytes);
    _lastImagePulledHash = _hash(pulledBytes);
  }

  // ---- incoming (cloud relay) ----

  /// Apply a `ClipboardPayload` forwarded by the cloud relay (already filtered
  /// to `type == 'clipboard'` from another sender — see [ClipboardRelay]).
  void applyRelayPayload(Map<String, dynamic> payload) {
    if (!_enabled) return;
    final alias = payload['alias'] as String? ?? 'A device';
    final sender = payload['sender'] as String?;
    if (payload['kind'] == 'image') {
      if (!_includeImages || !imagesSupported) return;
      final data = payload['data'] as String?;
      if (data == null || data.isEmpty) return;
      try {
        final bytes = base64Decode(data);
        if (bytes.isEmpty || bytes.length > _maxImageBytes) return;
        unawaited(
          _applyImage(
            bytes,
            payload['mime'] as String? ?? 'image/png',
            alias,
            sender,
          ),
        );
      } on FormatException {
        // malformed relay payload — ignore
      }
      return;
    }
    final text = payload['text'] as String? ?? '';
    if (text.isEmpty || text == _lastText) return;
    _applyText(text, alias, sender);
  }

  // ---- helpers ----

  static String _hash(Uint8List bytes) => sha256.convert(bytes).toString();

  /// A ≤8KB base64 JPEG thumbnail for the announce `preview` field, or null
  /// when one can't be made. Decode+resize runs in a background isolate — a
  /// multi-MB screenshot must not jank the UI isolate.
  static Future<String?> _makePreview(Uint8List bytes) async {
    try {
      final thumb = await compute(_encodePreview, bytes);
      if (thumb == null) return null;
      final b64 = base64Encode(thumb);
      return b64.length <= 8 * 1024 ? b64 : null;
    } on Object {
      return null;
    }
  }

  Future<void> dispose() async {
    _stop();
    relay?.setEnabled(false);
  }
}

/// Isolate entry: decode → fit within 96px → JPEG. Steps quality down until
/// the thumbnail fits the 8KB budget (base64 expands 4/3 → ~6KB raw).
Uint8List? _encodePreview(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var thumb = decoded;
  if (decoded.width > 96 || decoded.height > 96) {
    final wide = decoded.width >= decoded.height;
    thumb = img.copyResize(
      decoded,
      width: wide ? 96 : null,
      height: wide ? null : 96,
    );
  }
  for (final quality in const [60, 40, 25]) {
    final jpg = img.encodeJpg(thumb, quality: quality);
    if (jpg.length <= 6 * 1024) return Uint8List.fromList(jpg);
  }
  return null;
}
