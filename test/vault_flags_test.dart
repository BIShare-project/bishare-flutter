import 'dart:convert';

import 'package:bishare/core/config/feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// drive-plan.md task 3.1: the Drive entry stays hidden unless vault_enabled
/// is on, or "internal" on a device whose tester switch is on.
void main() {
  // The test binding answers every HTTP request with 400, so the background
  // refresh in load() never reaches the network and the cache holds.
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<FeatureFlags> withFlags(Map<String, Object?>? flags, {bool tester = false}) async {
    SharedPreferences.setMockInitialValues({
      if (flags != null) 'featureFlagsCache': jsonEncode(flags),
      if (tester) 'vaultTester': true,
    });
    final f = FeatureFlags(await SharedPreferences.getInstance());
    await f.load();
    return f;
  }

  test('absent, false or an unknown value: hidden', () async {
    for (final flags in [null, <String, Object?>{}, {'vault_enabled': false}, {'vault_enabled': 'yes'}, {'vault_enabled': 1}]) {
      final f = await withFlags(flags, tester: true);
      expect(f.vaultVisible, isFalse, reason: '$flags');
      expect(f.vaultOpen, isFalse);
    }
  });

  test('true: visible to everyone', () async {
    final f = await withFlags({'vault_enabled': true});
    expect(f.vaultOpen, isTrue);
    expect(f.vaultVisible, isTrue);
  });

  test('"internal": visible only with the tester switch', () async {
    final f = await withFlags({'vault_enabled': 'internal'});
    expect(f.vaultInternal, isTrue);
    expect(f.vaultVisible, isFalse);
    await f.setVaultTester(true);
    expect(f.vaultVisible, isTrue);
    await f.setVaultTester(false);
    expect(f.vaultVisible, isFalse);
  });
}
