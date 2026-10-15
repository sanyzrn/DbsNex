import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/expenses/expenses_screen.dart';
import 'expense_test_store.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late ExpenseFaultStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'expense_widget_fault_');
    store = ExpenseFaultStore(h.services);
  });
  tearDown(() => h.dispose());
  Future<void> host(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: nexLightTheme(),
        home: ExpensesScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String item) async {
    await tap(tester, find.byType(PopupMenuButton<String>));
    await tap(tester, find.text(item).last);
  }

  testWidgets(
    'failed payment save retains input; stable retry creates one record',
    (tester) async {
      await host(tester);
      await tap(tester, find.byKey(const ValueKey('expenses-add')));
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '۱۲٫۵',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expenses-note')),
        'Unfinished note',
      );
      store.failAfterTx = true;
      await tap(tester, find.byKey(const ValueKey('expenses-save')));
      expect(find.text('New expense'), findsOneWidget);
      expect(find.text('Unfinished note'), findsOneWidget);
      expect(await store.list('tx'), isEmpty);
      final draft = (await store.get('draft', 'tx:new'))!;
      final id = (draft['fields'] as Map)['recordId'];
      await tap(tester, find.byKey(const ValueKey('expenses-save')));
      expect(await store.list('tx'), hasLength(1));
      expect((await store.list('tx')).single.id, id);
      expect((await store.get('tx', id as String))!['amount'], 1250);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('invalid raw draft survives close and screen disposal', (
    tester,
  ) async {
    await host(tester);
    await tap(tester, find.byKey(const ValueKey('expenses-add')));
    await tester.enterText(
      find.byKey(const ValueKey('expenses-amount')),
      '۱۲..',
    );
    await tester.enterText(
      find.byKey(const ValueKey('expenses-note')),
      'Typed note',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, find.text('Keep draft & close'));
    final raw = await store.get('draft', 'tx:new');
    expect(raw, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await host(tester);
    await tap(tester, find.byKey(const ValueKey('expenses-add')));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('expenses-amount')))
          .controller!
          .text,
      '۱۲..',
    );
    expect(find.text('Typed note'), findsOneWidget);
    expect(await store.list('tx'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed draft read blocks replacement and supports Retry', (
    tester,
  ) async {
    final draft = {
      'v': 1,
      'base': '{}',
      'fields': {'amount': '125', 'note': 'Saved draft', 'recordId': 'stable'},
    };
    await store.put('draft', 'tx:new', draft);
    await host(tester);
    store.failDraftRead = true;
    await tap(tester, find.byKey(const ValueKey('expenses-add')));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(const ValueKey('expenses-save')), findsNothing);
    store.failDraftRead = false;
    expect(await store.get('draft', 'tx:new'), draft);
    await tap(tester, find.text('Retry'));
    expect(find.text('Saved draft'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('expenses-save')));
    expect((await store.list('tx')).single.id, 'stable');
    expect(tester.takeException(), isNull);
  });
  testWidgets('zero budget in tomans saves and has meaningful zero progress', (
    tester,
  ) async {
    await host(tester);
    await menu(tester, 'Budgets');
    await tester.enterText(find.byKey(const ValueKey('expenses-amount')), '۰');
    await tap(tester, find.text('Tomans'));
    await tap(tester, find.byKey(const ValueKey('expenses-budget-save')));
    expect((await store.list('budget')).single.body['amount'], 0);
    expect(find.text('Save'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'template errors and write failures keep the editor, retry once',
    (tester) async {
      await host(tester);
      await menu(tester, 'Templates');
      await tap(tester, find.byKey(const ValueKey('expenses-new-template')));
      await tap(tester, find.byKey(const ValueKey('expenses-template-save')));
      expect(find.text('Give the template a name'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('expenses-template-name')),
        'Monthly item',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '123',
      );
      store.failAfterKind = 'tpl';
      await tap(tester, find.byKey(const ValueKey('expenses-template-save')));
      expect(
        find.byKey(const ValueKey('expenses-template-save')),
        findsOneWidget,
      );
      expect(await store.list('tpl'), isEmpty);
      await tap(tester, find.byKey(const ValueKey('expenses-template-save')));
      expect(await store.list('tpl'), hasLength(1));
      expect(find.text('Monthly item'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'category list updates immediately and Undo restores its stable ID',
    (tester) async {
      await host(tester);
      await menu(tester, 'Categories');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('expenses-new-category')),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-new-category')),
        'Named category',
      );
      await tap(tester, find.byKey(const ValueKey('expenses-add-category')));
      final id = (await store.list('cat')).single.id;
      expect(find.text('Named category'), findsOneWidget);
      await tap(tester, find.byTooltip('Delete'));
      await tap(tester, find.text('Delete').last);
      expect(await store.get('cat', id), isNull);
      expect(find.text('Named category'), findsNothing);
      await tap(tester, find.text('Undo'));
      expect((await store.list('cat')).single.id, id);
      expect(find.text('Named category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('an incomplete payment cannot invent a date when repaired', (
    tester,
  ) async {
    final raw = {
      'type': 'expense',
      'amount': 125,
      'currency': 'USD',
      'note': 'Incomplete',
    };
    await store.put('tx', 'bad', raw);
    await host(tester);
    await tap(tester, find.text('All time').first);
    await tap(tester, find.byKey(const ValueKey('expenses-tx-bad')));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('expenses-date')),
        matching: find.text('Choose a valid date'),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('expenses-amount')),
      '1.25',
    );
    await tap(tester, find.byKey(const ValueKey('expenses-save')));
    expect(find.byKey(const ValueKey('expenses-save')), findsOneWidget);
    expect(await store.get('tx', 'bad'), raw);
    expect(tester.takeException(), isNull);
  });
}
