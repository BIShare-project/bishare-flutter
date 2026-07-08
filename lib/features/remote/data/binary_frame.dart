import 'dart:convert';
import 'dart:typed_data';

/// BIShare binary-protocol message types (byte-exact with the Rust/Swift
/// `BIShareProtocol`). Used by the stream-relay transport.
class FrameType {
  FrameType._();
  static const int prepare = 0x01;
  static const int prepareAck = 0x02;
  static const int fileStart = 0x03;
  static const int fileData = 0x04;
  static const int fileEnd = 0x05;
  static const int sessionEnd = 0x06;
  static const int cancel = 0x07;
  static const int error = 0x08;
}

/// A decoded binary frame.
class BinaryFrame {
  const BinaryFrame(this.type, this.fileId, this.payload);
  final int type;
  final int fileId;
  final Uint8List payload;
}

const int _headerSize = 9; // [type:1][len:4 BE][fileId:4 BE]

/// Encode a frame: `[type:1][length:4 BE][fileId:4 BE][payload]`.
Uint8List encodeFrame(int type, int fileId, List<int> payload) {
  final out = Uint8List(_headerSize + payload.length);
  final view = ByteData.sublistView(out);
  view.setUint8(0, type);
  view.setUint32(1, payload.length, Endian.big);
  view.setUint32(5, fileId, Endian.big);
  out.setAll(_headerSize, payload);
  return out;
}

/// Encode a JSON value as a frame payload.
Uint8List encodeJsonFrame(int type, int fileId, Object json) =>
    encodeFrame(type, fileId, utf8.encode(jsonEncode(json)));

/// Incrementally decodes frames from a byte stream (frames may span or share
/// WebSocket messages). Feed each incoming chunk to [add]; it yields every
/// complete frame and buffers any partial tail for the next call.
class FrameDecoder {
  Uint8List _buffer = Uint8List(0);

  Iterable<BinaryFrame> add(Uint8List data) sync* {
    _buffer = _buffer.isEmpty ? data : _concat(_buffer, data);
    var offset = 0;
    while (_buffer.length - offset >= _headerSize) {
      final view = ByteData.sublistView(_buffer, offset, offset + _headerSize);
      final type = view.getUint8(0);
      final len = view.getUint32(1, Endian.big);
      final fileId = view.getUint32(5, Endian.big);
      final frameEnd = offset + _headerSize + len;
      if (_buffer.length < frameEnd) break; // incomplete — wait for more
      yield BinaryFrame(
        type,
        fileId,
        Uint8List.sublistView(_buffer, offset + _headerSize, frameEnd),
      );
      offset = frameEnd;
    }
    _buffer = offset == 0
        ? _buffer
        : Uint8List.sublistView(_buffer, offset).sublist(0);
  }

  static Uint8List _concat(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length + b.length);
    out.setAll(0, a);
    out.setAll(a.length, b);
    return out;
  }
}
