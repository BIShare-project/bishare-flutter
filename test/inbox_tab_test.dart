import 'dart:convert';

import 'package:bishare/core/config/feature_flags.dart';
import 'package:bishare/core/di/locator.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/ui/app_showcase.dart';
import 'package:bishare/features/history/data/history_repository.dart';
import 'package:bishare/features/history/presentation/history_cubit.dart';
import 'package:bishare/features/history/presentation/history_page.dart';
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

  @override
  Stream<List<TransferRecord>> watchAll() => Stream.value(const []);
}

/// Kotak Masuk (redesign-plan.md 2.2): the received files and the transfer
/// history are two segments of one tab; Drive is a tab of its own, so the
/// switch never offers it, whatever the vault flag says.
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
        home: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => InboxCubit(_History())),
            BlocProvider(create: (_) => HistoryCubit(_History())),
          ],
          child: const InboxTab(),
        ),
      ),
    );
    await tester.pump();
  }

  for (final flags in <Map<String, Object?>?>[
    null,
    {'vault_enabled': true},
  ]) {
    testWidgets('received first, history second, no Drive (flags $flags)', (
      tester,
    ) async {
      await pump(tester, flags);
      final page = tester.widget<InboxPage>(find.byType(InboxPage));
      expect(page.segment, isNotNull);
      expect(find.text('history.received'), findsOneWidget);
      expect(find.text('history.title'), findsOneWidget);
      expect(find.text('inbox.segment_drive'), findsNothing);
      expect(find.byType(HistoryPage), findsNothing);
    });
  }
}
