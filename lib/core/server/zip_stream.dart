import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:path/path.dart' as p;

/// A true-streaming ZIP encoder for the Web-Share browser endpoints.
///
/// Why not `package:archive`'s `ZipEncoder`/`ZipFileEncoder`? Its API is fully
/// synchronous: `add()` writes an entire entry into the `OutputStream` in one
/// call (and the deflate path even buffers the whole compressed file in RAM
/// first). Feeding that into an HTTP response means either a full temp file
/// (what `/api/v1/download-all` used to do) or an unbounded in-memory buffer
/// whenever the browser downloads slower than the disk reads — a 10 GB folder
/// would OOM the app. An `async*` generator, by contrast, is pulled by
/// `shelf`/`dart:io` with real backpressure, so memory stays O(chunk).
///
/// Format choices (deliberately boring, maximum-compatibility):
/// * **Store only** (no deflate). Web-Share zips are transport containers —
///   the dominant content (media, archives) is incompressible, and store keeps
///   the encoder single-purpose and allocation-free. Matches what the
///   `Compression::Zstd` plan note calls "opsional".
/// * **Two passes per file** (CRC pass, then data pass) instead of bit-3 data
///   descriptors, so every local header is complete and any unzip
///   implementation — including picky ones — extracts it.
/// * **ZIP64** headers are emitted per entry / end-record only when a size,
///   offset, or entry count actually overflows the classic 32/16-bit fields,
///   so >4 GB files and >4 GB archives work while small zips stay classic.
///
/// The CRC comes from `package:archive`'s `getCrc32` (same table the rest of
/// the app uses).
class ZipStreamEntry {
  ZipStreamEntry({required this.name, this.file})
    : assert(name != ''),
      assert(
        file != null || name.endsWith('/'),
        'directory entries must end with /',
      );

  /// Path inside the zip, '/'-separated. A trailing '/' marks a directory
  /// entry (then [file] is null).
  final String name;

  /// The file to stream, or null for a directory entry.
  final File? file;

  bool get isDirectory => file == null;
}

/// Collects [ZipStreamEntry]s for the subtree at [dir]: every regular file
/// (dotfiles and in-flight `.part` temps excluded), plus explicit entries for
/// directories that would otherwise be lost (empty ones). Names are relative
/// to [dir], '/'-separated, sorted for a deterministic archive.
List<ZipStreamEntry> zipEntriesForDirectory(Directory dir) {
  final entries = <ZipStreamEntry>[];
  void walk(Directory d, String prefix) {
    final children = d.listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    var kept = 0;
    for (final child in children) {
      final name = p.basename(child.path);
      if (name.startsWith('.')) continue; // hidden + .browser-*.part temps
      if (child is File) {
        entries.add(ZipStreamEntry(name: '$prefix$name', file: child));
        kept++;
      } else if (child is Directory) {
        walk(child, '$prefix$name/');
        kept++;
      }
    }
    // Keep empty directories visible in the archive.
    if (kept == 0 && prefix.isNotEmpty) {
      entries.add(ZipStreamEntry(name: prefix));
    }
  }

  walk(dir, '');
  return entries;
}

/// Streams a ZIP archive of [entries] with backpressure (see library comment).
/// Throws [FileSystemException]/[StateError] mid-stream if a file vanishes or
/// shrinks while being read — the HTTP response then aborts, which is the
/// honest failure mode (a silently-padded archive would hide corruption).
Stream<List<int>> zipStream(List<ZipStreamEntry> entries) async* {
  const limit32 = 0xFFFFFFFF;
  const limit16 = 0xFFFF;

  var offset = 0;
  final central = <_CentralRecord>[];

  for (final entry in entries) {
    final nameBytes = utf8.encode(entry.name);
    final size = entry.isDirectory ? 0 : entry.file!.lengthSync();
    final modified = entry.isDirectory
        ? DateTime.now()
        : entry.file!.statSync().modified;

    // Pass 1: CRC-32 over exactly [size] bytes.
    var crc = 0;
    if (size > 0) {
      var counted = 0;
      await for (final chunk in entry.file!.openRead(0, size)) {
        crc = getCrc32(chunk, crc);
        counted += chunk.length;
      }
      if (counted != size) {
        throw StateError('zipStream: "${entry.name}" changed while zipping');
      }
    }

    final zip64 = size >= limit32;
    final w = _LeWriter()
      ..u32(0x04034b50) // local file header signature
      ..u16(zip64 ? 45 : 20) // version needed to extract
      ..u16(0x0800) // general purpose flags: UTF-8 names
      ..u16(0) // method: store
      ..u16(_dosTime(modified))
      ..u16(_dosDate(modified))
      ..u32(crc)
      ..u32(zip64 ? limit32 : size) // compressed size (== raw for store)
      ..u32(zip64 ? limit32 : size) // uncompressed size
      ..u16(nameBytes.length)
      ..u16(zip64 ? 20 : 0) // extra length
      ..bytes(nameBytes);
    if (zip64) {
      w
        ..u16(0x0001) // ZIP64 extra field id
        ..u16(16)
        ..u64(size) // uncompressed
        ..u64(size); // compressed
    }
    final header = w.take();

    central.add(
      _CentralRecord(
        nameBytes: nameBytes,
        crc: crc,
        size: size,
        localOffset: offset,
        dosTime: _dosTime(modified),
        dosDate: _dosDate(modified),
        isDirectory: entry.isDirectory,
      ),
    );

    yield header;
    if (size > 0) {
      // Pass 2: the data itself, straight off disk — the consumer's pace
      // drives the reads (backpressure), nothing is accumulated.
      var streamed = 0;
      await for (final chunk in entry.file!.openRead(0, size)) {
        streamed += chunk.length;
        yield chunk;
      }
      if (streamed != size) {
        throw StateError('zipStream: "${entry.name}" changed while zipping');
      }
    }
    offset += header.length + size;
  }

  // Central directory.
  final cdStart = offset;
  var cdSize = 0;
  for (final r in central) {
    final sizeOver = r.size >= limit32;
    final offsetOver = r.localOffset >= limit32;
    final zip64 = sizeOver || offsetOver;
    final extraLen = zip64 ? 4 + (sizeOver ? 16 : 0) + (offsetOver ? 8 : 0) : 0;
    final w = _LeWriter()
      ..u32(0x02014b50) // central directory header signature
      ..u16(zip64 ? 45 : 20) // version made by (host 0 = DOS attrs)
      ..u16(zip64 ? 45 : 20) // version needed
      ..u16(0x0800)
      ..u16(0) // store
      ..u16(r.dosTime)
      ..u16(r.dosDate)
      ..u32(r.crc)
      ..u32(sizeOver ? limit32 : r.size)
      ..u32(sizeOver ? limit32 : r.size)
      ..u16(r.nameBytes.length)
      ..u16(extraLen)
      ..u16(0) // comment length
      ..u16(0) // disk number start
      ..u16(0) // internal attributes
      ..u32(r.isDirectory ? 0x10 : 0) // external: DOS directory bit
      ..u32(offsetOver ? limit32 : r.localOffset)
      ..bytes(r.nameBytes);
    if (zip64) {
      w
        ..u16(0x0001)
        ..u16(extraLen - 4);
      if (sizeOver) {
        w
          ..u64(r.size)
          ..u64(r.size);
      }
      if (offsetOver) w.u64(r.localOffset);
    }
    final bytes = w.take();
    cdSize += bytes.length;
    yield bytes;
  }

  // End of central directory (+ ZIP64 records only when something overflows).
  final needZip64End =
      central.length > limit16 ||
      cdSize >= limit32 ||
      cdStart >= limit32;
  final end = _LeWriter();
  if (needZip64End) {
    final zip64EndOffset = cdStart + cdSize;
    end
      ..u32(0x06064b50) // ZIP64 end of central directory record
      ..u64(44) // size of the remainder of this record
      ..u16(45)
      ..u16(45)
      ..u32(0) // this disk
      ..u32(0) // cd disk
      ..u64(central.length)
      ..u64(central.length)
      ..u64(cdSize)
      ..u64(cdStart)
      ..u32(0x07064b50) // ZIP64 end of central directory locator
      ..u32(0)
      ..u64(zip64EndOffset)
      ..u32(1); // total disks
  }
  end
    ..u32(0x06054b50) // end of central directory
    ..u16(0)
    ..u16(0)
    ..u16(central.length > limit16 ? limit16 : central.length)
    ..u16(central.length > limit16 ? limit16 : central.length)
    ..u32(cdSize >= limit32 ? limit32 : cdSize)
    ..u32(cdStart >= limit32 ? limit32 : cdStart)
    ..u16(0); // comment length
  yield end.take();
}

int _dosTime(DateTime t) =>
    (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);

int _dosDate(DateTime t) {
  final year = t.year < 1980 ? 1980 : t.year;
  return ((year - 1980) << 9) | (t.month << 5) | t.day;
}

class _CentralRecord {
  _CentralRecord({
    required this.nameBytes,
    required this.crc,
    required this.size,
    required this.localOffset,
    required this.dosTime,
    required this.dosDate,
    required this.isDirectory,
  });

  final Uint8List nameBytes;
  final int crc;
  final int size;
  final int localOffset;
  final int dosTime;
  final int dosDate;
  final bool isDirectory;
}

/// Little-endian byte writer for the fixed-layout zip records.
class _LeWriter {
  final _builder = BytesBuilder(copy: false);

  void u16(int v) => _builder.add([v & 0xff, (v >> 8) & 0xff]);

  void u32(int v) => _builder.add([
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
  ]);

  void u64(int v) => _builder.add([
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
    (v >> 32) & 0xff,
    (v >> 40) & 0xff,
    (v >> 48) & 0xff,
    (v >> 56) & 0xff,
  ]);

  void bytes(List<int> data) => _builder.add(data);

  Uint8List take() => _builder.takeBytes();
}
