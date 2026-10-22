import 'package:bishare/core/di/locator.dart';
import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:bishare/features/vault/data/vault_keys.dart';
import 'package:bishare/features/vault/presentation/vault_desktop_pairing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _Account extends Mock implements VaultAccount {}

/// A Snap package reaches the system keyring only once the
/// password-manager-service interface is connected (audit D3): the pairing
/// then says so, with the command to run, instead of a bare "failed".
void main() {
  group('snapKeyringRefused', () {
    final refused = PlatformException(code: 'Libsecret error');
    test('a keyring error inside a Snap on Linux', () {
      expect(
        snapKeyringRefused(
          refused,
          linux: true,
          environment: {'SNAP': '/snap/bishare/1'},
        ),
        isTrue,
      );
    });
    test('not outside a Snap', () {
      expect(
        snapKeyringRefused(refused, linux: true, environment: {}),
        isFalse,
      );
    });
    test('not on another system', () {
      expect(
        snapKeyringRefused(
          refused,
          linux: false,
          environment: {'SNAP': '/snap/bishare/1'},
        ),
        isFalse,
      );
    });
    test('not for another kind of error', () {
      expect(
        snapKeyringRefused(
          StateError('x'),
          linux: true,
          environment: {'SNAP': '/snap/bishare/1'},
        ),
        isFalse,
      );
    });
  });

  late _Account account;
  setUp(() async {
    await getIt.reset();
    account = _Account();
    getIt.registerSingleton<VaultAccount>(account);
    when(
      () => account.startDesktopPairing(),
    ).thenThrow(PlatformException(code: 'Libsecret error'));
  });
  tearDown(() => keyringRefused = snapKeyringRefused);

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ShadApp(home: Scaffold(body: VaultDesktopPairingPanel())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a keyring error elsewhere: the plain failure, a new code to try',
    (tester) async {
      keyringRefused = (_) => false;
      await pump(tester);
      expect(find.text('vault.error_failed'), findsOneWidget);
      expect(find.text(snapKeyringCommand), findsNothing);
      expect(find.text('vault.pair_new_code'), findsOneWidget);
    },
  );

  testWidgets('the Snap keyring refused: the message and the command to copy', (
    tester,
  ) async {
    keyringRefused = (_) => true;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await pump(tester);
    expect(find.text('vault.error_snap_keyring'), findsOneWidget);
    expect(find.text(snapKeyringCommand), findsOneWidget);
    await tester.tap(find.byTooltip('common.copy'));
    await tester.pump();
    expect(copied, snapKeyringCommand);
    await tester.pump(const Duration(seconds: 5));
  });
}
