import 'package:bishare/core/crypto/e2e_crypto.dart';
import 'package:bishare/core/di/locator.dart';
import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/theme/app_theme.dart';
import 'package:bishare/features/vault/data/vault_api.dart';
import 'package:bishare/features/vault/data/vault_links.dart';
import 'package:bishare/features/vault/presentation/drive/drive_actions.dart';
import 'package:bishare/features/vault/presentation/drive/drive_controller.dart';
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Links extends Mock implements VaultLinks {}

/// The "Share as link" sheets (drive-plan.md 6B.3) with the server stood in
/// for: a lifetime is chosen, the link is made and shown, copied, emailed and
/// turned off; a link that already opens is offered first; a server error
/// makes no link.
void main() {
  late AppDatabase db;
  late _Links links;
  final folder = VaultObject(
    id: 'AAAAAAAAAAAAAAAAAAAAAA',
    name: 'Album',
    kind: 'dir',
    mtime: 0,
    hasThumb: false,
    seq: 1,
    createdAt: 0,
    encMeta: 'x',
  );
  VaultLink made(int days) => VaultLink(
    id: 'BBBBBBBBBBBBBBBBBBBBBB',
    url: '${VaultLinks.host}BBBBBBBBBBBBBBBBBBBBBB#key',
    folder: true,
    root: folder.id,
    name: 'Album',
    files: 3,
    createdAt: DateTime(2026, 10, 22),
    expiresAt: days == 0
        ? null
        : DateTime(2026, 10, 22).add(Duration(days: days)),
    opens: 0,
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableBuildModes = [];
    await EasyLocalization.ensureInitialized();
    registerFallbackValue(folder);
    registerFallbackValue(made(0));
  });

  setUp(() async {
    await getIt.reset();
    final prefs = await SharedPreferences.getInstance();
    final (crypto, _) = await E2ECrypto.create();
    db = AppDatabase(NativeDatabase.memory());
    links = _Links();
    getIt
      ..registerSingleton<AppDatabase>(db)
      ..registerSingleton<VaultLinks>(links)
      ..registerSingleton<DeviceIdentity>(
        DeviceIdentity.forTesting(
          fingerprint: 'fp',
          alias: 'Test Phone',
          crypto: crypto,
          deviceModel: 'Test Phone',
          deviceType: 'phone',
          prefs: prefs,
        ),
      );
  });
  tearDown(() => db.close());

  Future<DriveActions> pump(WidgetTester tester) async {
    late DriveActions act;
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        saveLocale: false,
        child: Builder(
          builder: (context) => ShadApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: AppTheme.light('blue'),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  act = DriveActions(context, DriveController(db.vaultDao));
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    // The translations load asynchronously, outside the fake clock.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    return act;
  }

  /// Sheets scroll when tall: what is tapped is scrolled into view first.
  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('a new link: lifetime, copy, email, turn off', (tester) async {
    when(() => links.list(root: folder.id)).thenAnswer((_) async => []);
    when(
      () => links.create(any(), days: any(named: 'days')),
    ).thenAnswer((i) async => made(i.namedArguments[#days] as int));
    when(
      () => links.email(
        any(),
        to: any(named: 'to'),
        name: any(named: 'name'),
      ),
    ).thenAnswer((_) async {});
    when(() => links.revoke(any())).thenAnswer((_) async {});
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
    final act = await pump(tester);

    var done = act.shareLink(folder);
    await tester.pumpAndSettle();
    expect(find.text('Share as link'), findsOneWidget);
    expect(find.text('7 days'), findsOneWidget);
    await tap(tester, find.text('Until I turn it off'));
    await tap(tester, find.text('Create link'));
    verify(() => links.create(folder, days: 0)).called(1);
    expect(find.text('Works until you turn it off'), findsOneWidget);
    expect(
      find.text('${VaultLinks.host}BBBBBBBBBBBBBBBBBBBBBB#key'),
      findsOneWidget,
    );

    await tap(tester, find.text('Copy link'));
    await done;
    expect(copied, '${VaultLinks.host}BBBBBBBBBBBBBBBBBBBBBB#key');
    await tester.pump(const Duration(seconds: 5));

    // Email: a wrong address is refused here, a right one goes to the server.
    when(() => links.list(root: folder.id)).thenAnswer((_) async => [made(0)]);
    done = act.shareLink(folder);
    await tester.pumpAndSettle();
    expect(
      find.text('New link'),
      findsOneWidget,
      reason: 'the open link is offered first',
    );
    await tap(tester, find.textContaining('Works until you turn it off'));
    await tap(tester, find.text('Email the link'));
    await tester.enterText(find.byType(EditableText), 'not-an-address');
    await tap(tester, find.text('Send'));
    await done;
    verifyNever(
      () => links.email(
        any(),
        to: any(named: 'to'),
        name: any(named: 'name'),
      ),
    );
    await tester.pump(const Duration(seconds: 5));

    done = act.shareLink(folder);
    await tester.pumpAndSettle();
    await tap(tester, find.textContaining('Works until you turn it off'));
    await tap(tester, find.text('Email the link'));
    await tester.enterText(find.byType(EditableText), 'friend@example.com');
    await tap(tester, find.text('Send'));
    await done;
    verify(
      () => links.email(any(), to: 'friend@example.com', name: 'Test Phone'),
    ).called(1);
    await tester.pump(const Duration(seconds: 5));

    // Turn off: asked first, then the server.
    done = act.shareLink(folder);
    await tester.pumpAndSettle();
    await tap(tester, find.textContaining('Works until you turn it off'));
    await tap(tester, find.text('Turn off link'));
    expect(find.text('Turn off this link?'), findsOneWidget);
    await tap(tester, find.text('Turn off link').last);
    await done;
    verify(() => links.revoke('BBBBBBBBBBBBBBBBBBBBBB')).called(1);
    await tester.pump(const Duration(seconds: 5));

    // A server error shows its message and no link. (One testWidgets: a
    // second one in this process never finishes loading the translations,
    // as store_screenshots_test.dart notes.)
    when(() => links.list(root: folder.id)).thenAnswer((_) async => []);
    when(
      () => links.create(any(), days: any(named: 'days')),
    ).thenThrow(const VaultApiException('VAULT_LINK_TOO_MANY', 'too many'));
    done = act.shareLink(folder);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Create link'));
    await done;
    verify(() => links.create(folder, days: 7)).called(1);
    expect(find.textContaining('too many files for one link'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
