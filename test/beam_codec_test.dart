import 'dart:math';
import 'dart:typed_data';

import 'package:bishare/features/qr_beam/domain/beam_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// QR Beam's wire format v1: a file goes out as frames and comes back whole,
/// whatever the chunk size the sender chose (the header names it) and in
/// whatever order the camera catches the frames.
void main() {
  Uint8List bytes(int n) {
    final r = Random(7);
    return Uint8List.fromList([for (var i = 0; i < n; i++) r.nextInt(256)]);
  }

  test('300 KB in 900-byte frames, caught out of order, comes back whole', () {
    final data = bytes(300 * 1024);
    final beam = encodeBeam(
      data,
      name: 'notes.pdf',
      mime: 'pdf',
      chunkSize: 900,
    );
    expect(beam.meta.total, (data.length / 900).ceil());
    final frames = [...beam.frames]..shuffle(Random(3));
    final c = BeamCollector();
    for (final f in frames) {
      c.add(f);
    }
    // A frame seen twice changes nothing.
    c.add(beam.frames[5]);
    expect(c.complete, isTrue);
    expect(c.assemble(), data);
    expect(c.meta!.name, 'notes.pdf');
  });

  test('the old 600-byte frames still decode', () {
    final data = bytes(50 * 1024);
    final beam = encodeBeam(data, name: 'a.txt', mime: 'txt');
    final c = BeamCollector();
    for (final f in beam.frames) {
      c.add(f);
    }
    expect(c.assemble(), data);
  });
}
