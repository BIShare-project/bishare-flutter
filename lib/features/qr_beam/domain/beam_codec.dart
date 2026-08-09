import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// QR Beam codec — offline file transfer over an animated stream of QR codes.
///
/// With no Wi-Fi, hotspot, or Bluetooth, the sender's screen loops a sequence of
/// QR frames and the receiver's camera scans them until every chunk is captured,
/// then reassembles the file. Purely optical (screen → camera), so it needs no
/// radios. Throughput is small — meant for small payloads (text, keys, small
/// docs), not media.
///
/// Wire format v1 — MUST stay byte-identical with the web/TS implementation
/// (src/lib/qrbeam/codec.ts) so any device can beam to any other:
///
///   Header frame: `BB1H` + base64url(JSON({ v:1, id, n:name, m:mime, s:size,
///                                            t:total, c:chunkSize }))
///   Data frame:   `BB1D` + id(6 hex) + index(6 hex) + base64url(chunkBytes)
///
/// The sender loops [header, data0, data1, …]; the receiver collects unique
/// indices until it has `total` of them, then concatenates in index order.
const String beamMagic = 'BB1';
const int defaultChunkBytes = 600;

class BeamMeta {
  const BeamMeta({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.total,
    required this.chunkSize,
  });

  final String id;
  final String name;
  final String mime;
  final int size;
  final int total;
  final int chunkSize;
}

class EncodedBeam {
  const EncodedBeam(this.frames, this.meta);
  final List<String> frames;
  final BeamMeta meta;
}

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64urlDecode(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64Url.decode(s + ('=' * pad));
}

String _hex(int n, int width) => n.toRadixString(16).padLeft(width, '0');

String _randomId() {
  final r = Random.secure();
  final v = (r.nextInt(256) << 16) | (r.nextInt(256) << 8) | r.nextInt(256);
  return _hex(v, 6);
}

/// Build the full frame list for a payload. `frames[0]` is the header; the rest
/// are data frames in index order. The sender loops this list on screen.
EncodedBeam encodeBeam(
  Uint8List bytes, {
  required String name,
  required String mime,
  String? id,
  int chunkSize = defaultChunkBytes,
}) {
  final total = max(1, (bytes.length / chunkSize).ceil());
  final tid = id ?? _randomId();
  final meta = BeamMeta(
    id: tid,
    name: name,
    mime: mime.isEmpty ? 'application/octet-stream' : mime,
    size: bytes.length,
    total: total,
    chunkSize: chunkSize,
  );

  final headerBody = _b64url(utf8.encode(jsonEncode({
    'v': 1,
    'id': tid,
    'n': meta.name,
    'm': meta.mime,
    's': meta.size,
    't': total,
    'c': chunkSize,
  })));
  final header = '${beamMagic}H$headerBody';

  final frames = <String>[header];
  for (var i = 0; i < total; i++) {
    final end = min((i + 1) * chunkSize, bytes.length);
    final chunk = bytes.sublist(i * chunkSize, end);
    frames.add('${beamMagic}D$tid${_hex(i, 6)}${_b64url(chunk)}');
  }
  return EncodedBeam(frames, meta);
}

/// Accumulates scanned frames and reassembles the file when complete.
class BeamCollector {
  BeamMeta? meta;
  final Map<int, Uint8List> _chunks = {};

  bool get complete => meta != null && _chunks.length >= meta!.total;
  double get progress => meta == null ? 0 : min(1.0, _chunks.length / meta!.total);
  int get received => _chunks.length;
  int get total => meta?.total ?? 0;

  /// Feed a scanned frame string. Returns true if it was a valid, new frame.
  bool add(String frame) {
    if (!frame.startsWith(beamMagic)) return false;
    final type = frame[beamMagic.length];
    final body = frame.substring(beamMagic.length + 1);
    try {
      if (type == 'H') {
        if (meta != null) return false;
        final j = jsonDecode(utf8.decode(_b64urlDecode(body))) as Map<String, dynamic>;
        final m = BeamMeta(
          id: '${j['id']}',
          name: '${j['n'] ?? 'file'}',
          mime: '${j['m'] ?? 'application/octet-stream'}',
          size: (j['s'] ?? 0) as int,
          total: (j['t'] ?? 0) as int,
          chunkSize: (j['c'] ?? defaultChunkBytes) as int,
        );
        if (m.total <= 0) return false;
        meta = m;
        return true;
      }
      if (type == 'D') {
        final id = body.substring(0, 6);
        final index = int.parse(body.substring(6, 12), radix: 16);
        if (meta != null && id != meta!.id) return false;
        if (_chunks.containsKey(index)) return false;
        _chunks[index] = _b64urlDecode(body.substring(12));
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  /// Reassemble the file once [complete]; throws otherwise.
  Uint8List assemble() {
    final mm = meta;
    if (mm == null || !complete) throw StateError('beam not complete');
    final out = Uint8List(mm.size);
    var off = 0;
    for (var i = 0; i < mm.total; i++) {
      final c = _chunks[i];
      if (c == null) throw StateError('missing chunk $i');
      out.setRange(off, off + c.length, c);
      off += c.length;
    }
    return out;
  }
}
