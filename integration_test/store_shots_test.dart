import 'package:integration_test/integration_test.dart';

import '../test/preview/store_screenshots_test.dart' as shots;

/// The store screenshots drawn by a simulator instead of the test engine:
/// the device's own size, insets, side strips and fold (iPhone Duo), with the
/// same sample content as test/preview/store_screenshots_test.dart. Writes
/// the raw captures for store/screens/frame.py.
///
///   flutter test integration_test/store_shots_test.dart -d SIMULATOR_ID \
///     --dart-define=BISHARE_SHOTS_DEVICE=true \
///     --dart-define=BISHARE_SHOTS_ROOT=$PWD \
///     --dart-define=BISHARE_SHOTS_DIR=/tmp/raw \
///     --dart-define=BISHARE_SHOTS_PRESETS=ios_duo_outer \
///     --dart-define=BISHARE_SHOTS_LOCALES=en
///
/// The preset names the store size and the sample owner; the simulator must
/// be in that pose (iPhone Duo closed for ios_duo_outer, open for
/// ios_duo_inner).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  shots.main();
}
