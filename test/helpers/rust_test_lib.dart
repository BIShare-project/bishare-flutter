import 'dart:io';

import 'package:bishare/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

bool _ready = false;

/// Load the native `bishare_ffi` library into a plain `flutter test` run, so
/// tests can exercise the shared Rust code (BSE2 etc.) without a device.
///
/// CI builds `rust/target/release` before `flutter test`; locally run
/// `cargo build --manifest-path rust/Cargo.toml` once. Returns false when no
/// build exists so callers can `skip` with a clear reason — except on CI,
/// where a missing library is a broken pipeline, not an optional extra.
Future<bool> initRustForTests() async {
  if (_ready) return true;
  final ext = Platform.isMacOS
      ? 'dylib'
      : Platform.isWindows
      ? 'dll'
      : 'so';
  final prefix = Platform.isWindows ? '' : 'lib';
  final candidates = [
    'rust/target/release/${prefix}bishare_ffi.$ext',
    'rust/target/debug/${prefix}bishare_ffi.$ext',
  ];
  final path = candidates.cast<String?>().firstWhere(
    (p) => File(p!).existsSync(),
    orElse: () => null,
  );
  if (path == null) {
    if (Platform.environment['CI'] == 'true') {
      throw StateError(
        'native library not built — CI must run cargo build before flutter test '
        '(looked for ${candidates.join(', ')})',
      );
    }
    return false;
  }
  await RustLib.init(externalLibrary: ExternalLibrary.open(path));
  _ready = true;
  return true;
}

const rustUnavailableReason =
    'native library not built: run `cargo build --manifest-path rust/Cargo.toml`';
