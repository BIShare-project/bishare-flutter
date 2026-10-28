import 'dart:convert';
import 'dart:io';

import 'package:bishare/core/config/feature_flags.dart';
import 'package:bishare/core/di/locator.dart';
import 'package:bishare/features/remote/data/cloud_transfer_service.dart';
import 'package:bishare/features/remote/presentation/widgets/done_view.dart';
import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account extends Mock implements VaultAccount {}

/// Under a finished Secure Link (24 hours), the card that points to Drive for
/// a file that should stay longer: only while Drive is on for this device;
/// "Save to Drive" when Drive is set up here, "Set up Drive" when it is not.
void main() {
  const result = CloudUploadResult(
    code: 'ABC-DEF',
    rawCode: 'ABCDEF',
    deleteToken: 't',
    fileName: 'photo.jpg',
    fileSize: 1000,
  );
  late String sent;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('keep_longer');
    sent = '${dir.path}/photo.jpg';
    File(sent).writeAsBytesSync(List.filled(1000, 7));
  });

  Future<GoRouter> pump(
    WidgetTester tester, {
    Map<String, Object?>? flags,
    VaultStatus? drive,
    String? path,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (flags != null) 'featureFlagsCache': jsonEncode(flags),
    });
    final f = FeatureFlags(await SharedPreferences.getInstance());
    await tester.runAsync(f.load);
    await getIt.reset();
    getIt.registerSingleton<FeatureFlags>(f);
    if (drive != null) {
      final account = _Account();
      when(() => account.status).thenReturn(drive);
      getIt.registerSingleton<VaultAccount>(account);
    }
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: DoneView(result: result, path: path),
          ),
        ),
        GoRoute(
          path: '/drive-account',
          builder: (_, _) => const Text('account page'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('flag off: no card', (tester) async {
    await pump(tester, path: sent);
    expect(find.text('ABC-DEF'), findsOneWidget);
    expect(find.text('remote.keep_longer_title'), findsNothing);
  });

  testWidgets('"internal" without the tester switch: no card', (tester) async {
    await pump(tester, flags: {'vault_enabled': 'internal'}, path: sent);
    expect(find.text('remote.keep_longer_title'), findsNothing);
  });

  testWidgets('Drive not set up here: the card leads to setting it up', (
    tester,
  ) async {
    await pump(tester, flags: {'vault_enabled': true}, path: sent);
    expect(find.text('remote.keep_longer_title'), findsOneWidget);
    expect(find.text('remote.keep_longer_body'), findsOneWidget);
    expect(find.text('vault.save_to_drive'), findsNothing);
    await tester.tap(find.text('remote.keep_longer_setup'));
    await tester.pumpAndSettle();
    expect(find.text('account page'), findsOneWidget);
  });

  testWidgets('Drive ready: Save to Drive for the file that was sent', (
    tester,
  ) async {
    await pump(
      tester,
      flags: {'vault_enabled': true},
      drive: VaultStatus.ready,
      path: sent,
    );
    expect(find.text('vault.save_to_drive'), findsOneWidget);
    expect(find.text('remote.keep_longer_setup'), findsNothing);
  });

  testWidgets('Drive ready but the file is gone: no button', (tester) async {
    await pump(
      tester,
      flags: {'vault_enabled': true},
      drive: VaultStatus.ready,
      path: '${sent}_gone',
    );
    expect(find.text('remote.keep_longer_title'), findsOneWidget);
    expect(find.text('vault.save_to_drive'), findsNothing);
    expect(find.text('remote.keep_longer_setup'), findsNothing);
  });
}
