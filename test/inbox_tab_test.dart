import 'dart:convert';

import 'package:bishare/core/config/feature_flags.dart';
import 'package:bishare/core/di/locator.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/ui/app_showcase.dart';
import 'package:bishare/features/history/data/history_repository.dart';
import 'package:bishare/features/inbox/presentation/inbox_cubit.dart';
import 'package:bishare/features/inbox/presentation/inbox_page.dart';
import 'package:bishare/features/inbox/presentation/inbox_tab.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No database: a drift stream inside a widget test never settles.
class _History extends HistoryRepository {
  _History() : super(AppDatabase(NativeDatabase.memory()));

  @override
  Stream<List<TransferRecord>> watchReceived() => Stream.value(const []);
}

/// Drive lives in the Inbox tab as a second segment (drive-plan.md "Product
/// shape"), and only while the vault_enabled flag allows it: with the flag
/// off the tab must be the Inbox exactly as before.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  Future<void> pump(WidgetTester tester, Map<String, Object?>? flags) async {
    SharedPreferences.setMockInitialValues({
      if (flags != null) 'featureFlagsCache': jsonEncode(flags),
    });
    final f = FeatureFlags(await SharedPreferences.getInstance());
    await tester.runAsync(f.load);
    getIt
      ..allowReassignment = true
      ..registerSingleton<FeatureFlags>(f);
    final showcase = registerAppShowcase();
    addTearDown(showcase.unregister);
    await tester.pumpWidget(
      ShadApp(
        home: BlocProvider(
          create: (_) => InboxCubit(_History()),
          child: const InboxTab(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('flag off: the Inbox as it always was, no switch', (tester) async {
    await pump(tester, null);
    final page = tester.widget<InboxPage>(find.byType(InboxPage));
    expect(page.segment, isNull);
    expect(find.text('inbox.segment_drive'), findsNothing);
  });

  testWidgets('flag on: the switch under the title, Inbox first', (tester) async {
    await pump(tester, {'vault_enabled': true});
    final page = tester.widget<InboxPage>(find.byType(InboxPage));
    expect(page.segment, isNotNull);
    expect(find.text('inbox.segment_device'), findsOneWidget);
    expect(find.text('inbox.segment_drive'), findsOneWidget);
  });

  testWidgets('"internal" without the tester switch: hidden', (tester) async {
    await pump(tester, {'vault_enabled': 'internal'});
    expect(tester.widget<InboxPage>(find.byType(InboxPage)).segment, isNull);
  });
}
