/// Compile-time build variants.
///
/// `BISHARE_FOSS=true` (via `--dart-define`) marks the fully-free build used
/// for F-Droid: camera QR scanning is disabled (mobile_scanner bundles
/// Google's proprietary MLKit on Android — the F-Droid build swaps the
/// package for the pure-Dart stub in `fdroid/mobile_scanner_stub` via
/// `tool/foss_flavor.sh`), and anonymous usage telemetry flips to opt-in.
const bool kFossBuild = bool.fromEnvironment('BISHARE_FOSS');
