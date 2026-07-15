import 'dart:convert';

import '../../src/rust/api/manifest.dart' as ffi;
import 'sync_models.dart';

/// The `manifest_diff` FFI shape, injectable so [DeltaEngine] is unit-testable
/// without a loaded native library.
typedef ManifestDiffFn = Future<String> Function({
  required String localJson,
  required String remoteJson,
});

/// Turns two manifests into the ordered [DeltaOp]s that transform `local` into
/// `remote`, delegating the actual diff (with rename detection) to the shared
/// Rust `manifest_diff` — the SAME engine used on both the LAN and cloud paths,
/// so a rename is detected identically everywhere. FRB runs it on its worker
/// pool, so diffing a large tree never blocks the Dart isolate.
class DeltaEngine {
  DeltaEngine({ManifestDiffFn? diff}) : _diff = diff ?? ffi.manifestDiff;

  final ManifestDiffFn _diff;

  /// Ops that make a peer holding [local] match [remote]. On the pull side,
  /// swap the arguments — the diff is directional.
  Future<List<DeltaOp>> diff({
    required List<ManifestEntry> local,
    required List<ManifestEntry> remote,
  }) async {
    final resultJson = await _diff(
      localJson: _encode(local),
      remoteJson: _encode(remote),
    );
    final decoded = jsonDecode(resultJson);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DeltaOp.fromJson)
        .toList(growable: false);
  }

  static String _encode(List<ManifestEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());
}
