import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/controller.dart';
import 'package:nex_client/modules/expenses/expenses_screen.dart';
import 'package:nex_client/modules/expenses/logic.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// The audit's regression net — the places this pass changed, held in place:
/// the money a unit switch must never change, a form that opens untouched,
/// day and month groups, the six-month trend, carried-over budgets, a
/// renamed category, a repeated payment, and a Persian search that finds
/// what the person typed on another keyboard.
ExpenseTx tx(
  String id,
  DateTime date, {
  String type = 'expense',
  int amountRial = 1000,
  String? category = 'cat-groceries',
  String? note,
  String? merchant,
  String? account,
  String? templateId,
  String? period,
  bool valid = true,
}) => ExpenseTx(
  id: id,
  type: type,
  amountRial: amountRial,
  date: date,
  categoryId: category,
  note: note,
  merchant: merchant,
  account: account,
  templateId: templateId,
  period: period,
  valid: valid,
);

String nameOf(String id) => switch (id) {
  'cat-groceries' => 'Groceries',
  'cat-rent' => 'Rent',
  _ => 'Other',
};

void main() {
  group('a Persian search finds what the person meant', () {
    test('the letters one keyboard writes two ways are one letter', () {
      expect(foldExpenseSearch('كتاب'), 'کتاب');
      expect(foldExpenseSearch('علي'), 'علی');
      expect(foldExpenseSearch('مصطفى'), 'مصطفی');
      expect(foldExpenseSearch('أمر'), 'امر');
      expect(foldExpenseSearch('مسئله'), 'مسیله');
      expect(foldExpenseSearch('کتـــاب'), 'کتاب');
      expect(foldExpenseSearch('کتاب‌ها'), 'کتابها');
      expect(foldExpenseSearch('مُهَمّ'), 'مهم');
      expect(foldExpenseSearch('۱۴۰۴'), '1404');
      expect(foldExpenseSearch('٢٠٢٥'), '2025');
    });

    test('a bakery written either way is found', () {
      final txs = [
        tx('a', DateTime(2026, 11, 5), note: 'نانوائي'),
        tx('b', DateTime(2026, 11, 6), note: 'سوپر'),
      ];
      expect(
        filterTxs(txs, query: 'نانوایی', categoryName: nameOf).map((t) => t.id),
        ['a'],
      );
      expect(
        filterTxs(txs, query: 'نانوائی', categoryName: nameOf).map((t) => t.id),
        ['a'],
      );
    });
  });

  group('records grouped the way a person reads them', () {
    test('one group a day, newest day first, undated last', () {
      final groups = expenseDayGroups([
        tx('a', DateTime(2026, 11, 5, 9), amountRial: 100),
        tx('b', DateTime(2026, 11, 5, 20), amountRial: 200),
        tx('c', DateTime(2026, 11, 4, 12), amountRial: 400),
        tx('d', DateTime(2026, 11, 6), amountRial: 900, valid: false),
        tx('e', DateTime(1970), amountRial: 50, valid: false),
      ]);
      // A dated record keeps its own day even when it needs repair; one
      // whose date cannot be read has a group of its own, last.
      expect(groups.map((g) => g.day?.day), [6, 5, 4, null]);
      final fifth = groups[1];
      // Newest record of the day first, and only the readable ones counted.
      expect(fifth.txs.map((t) => t.id), ['b', 'a']);
      expect(fifth.totals.expense, BigInt.from(300));
      expect(groups.first.totals.expense, BigInt.zero);
      expect(groups.last.txs.map((t) => t.id), ['e']);
      expect(groups.last.totals.expense, BigInt.zero);
    });

    test('a month of the all-time view keeps its own totals', () {
      final sections = expenseMonthSections([
        tx('a', DateTime(2026, 10, 3), amountRial: 100),
        tx('b', DateTime(2026, 10, 20), amountRial: 200),
        tx('c', DateTime(2026, 11, 2), amountRial: 500),
      ], solar: false);
      expect(sections.length, 2);
      expect(sections.first.month, const NexModuleMonth(false, 2026, 11));
      expect(sections.first.totals.expense, BigInt.from(500));
      expect(sections.last.totals.expense, BigInt.from(300));
    });

    test('the trend is six real months, oldest first', () {
      final month = NexModuleMonth(false, 2026, 11);
      final points = expenseTrend(
        [
          tx('a', DateTime(2026, 11, 2), amountRial: 300),
          tx('b', DateTime(2026, 9, 2), amountRial: 900),
          tx('c', DateTime(2026, 11, 3), type: 'income', amountRial: 5000),
        ],
        month: month,
        solar: false,
        count: 6,
      );
      expect(points.length, 6);
      expect(points.first.month, const NexModuleMonth(false, 2026, 6));
      expect(points.last.month, month);
      expect(points.last.spent, BigInt.from(300));
      expect(points[3].month, const NexModuleMonth(false, 2026, 9));
      expect(points[3].spent, BigInt.from(900));
      // A month with nothing entered is a real zero.
      expect(points.first.spent, BigInt.zero);
      // Income is not spending.
      expect(points.last.spent, BigInt.from(300));
    });
  });

  group('the controller', () {
    late NexTestHarness harness;
    late NexModuleStore store;
    late ExpensesController controller;

    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_expaudit_');
      store = NexModuleStore(harness.services, 'expenses');
      controller = ExpensesController(store);
      await controller.load();
    });

    tearDown(() async {
      controller.dispose();
      await harness.dispose();
    });

    test(
      'last month’s budgets are carried over once, never over ones here',
      () async {
        await controller.saveBudget(
          const ExpenseBudget(start: '2026-10-01', amountRial: 2000000),
        );
        await controller.saveBudget(
          const ExpenseBudget(
            start: '2026-10-01',
            categoryId: 'cat-groceries',
            amountRial: 900000,
          ),
        );
        await controller.saveBudget(
          const ExpenseBudget(
            start: '2026-11-01',
            categoryId: 'cat-groceries',
            amountRial: 1000000,
          ),
        );
        final created = await controller.copyBudgetsFrom(
          from: '2026-10-01',
          to: '2026-11-01',
        );
        expect(created, ['budget-2026-11-01-all']);
        expect(controller.budgetFor('2026-11-01', null)!.amountRial, 2000000);
        // The category budget chosen for November is untouched.
        expect(
          controller.budgetFor('2026-11-01', 'cat-groceries')!.amountRial,
          1000000,
        );
        await controller.clearBudgets(created);
        expect(controller.budgetFor('2026-11-01', null), isNull);
        expect(controller.budgetFor('2026-11-01', 'cat-groceries'), isNotNull);
      },
    );

    test(
      'a repeated payment keeps the words and drops the recurrence link',
      () async {
        await controller.saveTx(
          ExpenseTx(
            id: 'tx-1',
            type: 'expense',
            amountRial: 25000,
            date: DateTime(2026, 10, 5, 12),
            categoryId: 'cat-groceries',
            note: 'نان',
            templateId: 'tpl-1',
            period: '2026-10-01',
          ),
        );
        final at = DateTime(2026, 11, 23, 18, 30);
        final id = await controller.duplicateTx(
          controller.txById('tx-1')!,
          at: at,
        );
        expect(id, isNot('tx-1'));
        final copy = controller.txById(id)!;
        expect(copy.amountRial, 25000);
        expect(copy.note, 'نان');
        expect(copy.categoryId, 'cat-groceries');
        expect(copy.date, at);
        expect(copy.templateId, isNull);
        expect(copy.period, isNull);
        // The original is untouched.
        expect(controller.txById('tx-1')!.templateId, 'tpl-1');
      },
    );

    test('renaming a category keeps its id and its records', () async {
      await controller.addCategory('نان', id: 'cat-my-bread');
      await controller.saveTx(
        ExpenseTx(
          id: 'tx-1',
          type: 'expense',
          amountRial: 5000,
          date: DateTime(2026, 11, 5),
          categoryId: 'cat-my-bread',
        ),
      );
      final category = controller.customCategories.single;
      await controller.renameCategory(category, 'نان سنگک');
      expect(controller.customCategories.single.label, 'نان سنگک');
      expect(controller.txById('tx-1')!.categoryId, 'cat-my-bread');
      final raw = await store.get('cat', 'cat-my-bread');
      expect(raw!['label'], 'نان سنگک');
    });
  });

  group('the screen', () {
    late NexTestHarness harness;
    late NexModuleStore store;

    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_expscreen_');
      store = NexModuleStore(harness.services, 'expenses');
    });
    tearDown(() async => harness.dispose());

    Future<void> pumpScreen(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      Size size = const Size(800, 1600),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ExpensesScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
    }

    String amountText(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const ValueKey('expenses-amount')))
        .controller!
        .text;

    testWidgets('switching the unit re-words the money, never changes it', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rials'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '1250005',
      );
      await tester.pumpAndSettle();
      expect(amountText(tester), '1,250,005');
      await tester.tap(find.text('Tomans'));
      await tester.pumpAndSettle();
      // One rial of remainder is a tenth of a toman: it stays on screen.
      expect(amountText(tester), '125,000.5');
      await tester.tap(find.text('Rials'));
      await tester.pumpAndSettle();
      expect(amountText(tester), '1,250,005');
      await tester.tap(find.text('Tomans'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      final raw = (await store.list('tx')).single.body;
      expect(raw['amountRial'], 1250005);
    });

    testWidgets('a saved record opens untouched: Back needs no confirmation', (
      tester,
    ) async {
      await store.put('tx', 'tx-1', {
        'type': 'expense',
        'amountRial': 1250000,
        'date': DateTime.now().toIso8601String(),
        'category': 'cat-groceries',
        'note': 'Weekly shop',
      });
      await pumpScreen(tester);
      await tester.tap(find.text('Weekly shop'));
      await tester.pumpAndSettle();
      expect(amountText(tester), '125,000');
      final context = tester.element(
        find.byKey(const ValueKey('expenses-save')),
      );
      await Navigator.of(context).maybePop();
      await tester.pumpAndSettle();
      // It closed on the first Back: nothing was ever typed.
      expect(find.byKey(const ValueKey('expenses-save')), findsNothing);
      expect(find.text('Discard this entry?'), findsNothing);
    });

    testWidgets('typing still guards the form against a stray Back', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '250',
      );
      await tester.pumpAndSettle();
      final context = tester.element(
        find.byKey(const ValueKey('expenses-save')),
      );
      await Navigator.of(context).maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Discard this entry?'), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-save')), findsOneWidget);
    });

    testWidgets('records are grouped by day, with that day’s spending', (
      tester,
    ) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      await store.put('tx', 'tx-1', {
        'type': 'expense',
        'amountRial': 100000,
        'date': today.toIso8601String(),
        'category': 'cat-groceries',
        'note': 'Bread',
      });
      await store.put('tx', 'tx-2', {
        'type': 'expense',
        'amountRial': 50000,
        'date': today.add(const Duration(hours: 2)).toIso8601String(),
        'category': 'cat-food',
        'note': 'Tea',
      });
      await pumpScreen(tester);
      expect(
        find.byKey(ValueKey('expenses-day-${isoDay(today)}')),
        findsOneWidget,
      );
      // 150,000 rials of spending that day, said in tomans.
      expect(find.text('15,000 tomans'), findsWidgets);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('a filtered list does not claim a day’s full total', (
      tester,
    ) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      await store.put('tx', 'tx-1', {
        'type': 'expense',
        'amountRial': 100000,
        'date': today.toIso8601String(),
        'category': 'cat-groceries',
        'note': 'Bread',
      });
      await store.put('tx', 'tx-2', {
        'type': 'expense',
        'amountRial': 50000,
        'date': today.toIso8601String(),
        'category': 'cat-food',
        'note': 'Tea',
      });
      await pumpScreen(tester);
      final header = find.byKey(ValueKey('expenses-day-${isoDay(today)}'));
      expect(
        find.descendant(of: header, matching: find.text('15,000 tomans')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Search payments'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-search')),
        'Bread',
      );
      await tester.pumpAndSettle();
      // The field itself carries the word too; the record is still there.
      expect(find.text('Bread'), findsWidgets);
      expect(
        find.descendant(of: header, matching: find.text('15,000 tomans')),
        findsNothing,
        reason: 'the filtered row is 10,000 of a 15,000 day',
      );
    });

    testWidgets('all time reads as months, each with its own total', (
      tester,
    ) async {
      final now = DateTime.now();
      final earlier = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 40));
      await store.put('tx', 'tx-1', {
        'type': 'expense',
        'amountRial': 300000,
        'date': now.toIso8601String(),
        'category': 'cat-groceries',
      });
      await store.put('tx', 'tx-2', {
        'type': 'expense',
        'amountRial': 700000,
        'date': earlier.toIso8601String(),
        'category': 'cat-rent',
      });
      await pumpScreen(tester);
      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      final thisMonth = NexModuleMonth.of(now, solar: false);
      final other = NexModuleMonth.of(earlier, solar: false);
      expect(
        find.byKey(
          ValueKey('expenses-month-section-${monthStartIso(thisMonth)}'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('expenses-month-section-${monthStartIso(other)}')),
        findsOneWidget,
      );
      expect(find.text('30,000 tomans'), findsWidgets);
      expect(find.text('70,000 tomans'), findsWidgets);
    });

    testWidgets('the six-month trend appears once there is spending', (
      tester,
    ) async {
      await store.put('tx', 'tx-1', {
        'type': 'expense',
        'amountRial': 300000,
        'date': DateTime.now().toIso8601String(),
        'category': 'cat-groceries',
      });
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('expenses-trend')), findsOneWidget);
      expect(find.text('Last six months'), findsOneWidget);
    });

    testWidgets(
      'a month is picked from a grid, and This month brings you back',
      (tester) async {
        await pumpScreen(tester);
        final now = DateTime.now();
        final base = NexModuleMonth.of(now, solar: false);
        final context = tester.element(find.byType(ExpensesScreen));
        await tester.tap(find.text(base.title(context)));
        await tester.pumpAndSettle();
        expect(find.text('Choose a month'), findsOneWidget);
        // Any month of the same year other than the one shown.
        final target = base.month == 1 ? 2 : 1;
        await tester.tap(
          find.byKey(ValueKey('expenses-month-${base.year}-$target')),
        );
        await tester.pumpAndSettle();
        final picked = NexModuleMonth(false, base.year, target);
        expect(find.text(picked.title(context)), findsOneWidget);
        expect(
          find.byKey(const ValueKey('expenses-this-month')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('expenses-this-month')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('expenses-this-month')), findsNothing);
      },
    );

    testWidgets('last month’s budgets can be carried over and undone', (
      tester,
    ) async {
      final now = DateTime.now();
      final thisMonth = NexModuleMonth.of(now, solar: false);
      final lastMonth = thisMonth.shift(-1);
      await store.put(
        'budget',
        budgetId(monthStartIso(lastMonth), null),
        ExpenseBudget(
          start: monthStartIso(lastMonth),
          amountRial: 2000000,
        ).toBody(),
      );
      await pumpScreen(tester);
      expect(
        find.byKey(const ValueKey('expenses-copy-budgets')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('expenses-copy-budgets')));
      await tester.pumpAndSettle();
      final copied = await store.get(
        'budget',
        budgetId(monthStartIso(thisMonth), null),
      );
      expect(copied!['amountRial'], 2000000);
      expect(find.textContaining('carried over'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        await store.get('budget', budgetId(monthStartIso(thisMonth), null)),
        isNull,
      );
    });

    testWidgets('a payment can be written again for today', (tester) async {
      await store.put('tx', 'tx-1', {
        'type': 'expense',
        'amountRial': 25000,
        'date': DateTime.now().toIso8601String(),
        'category': 'cat-transport',
        'note': 'Taxi',
      });
      await pumpScreen(tester);
      await tester.tap(find.text('Taxi'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-duplicate')));
      await tester.pumpAndSettle();
      final rows = await store.list('tx');
      expect(rows.length, 2);
      final copy = rows.firstWhere((row) => row.id != 'tx-1');
      expect(copy.body['amountRial'], 25000);
      expect(copy.body['note'], 'Taxi');
      expect(
        (copy.body['date'] as String).startsWith(isoDay(DateTime.now())),
        isTrue,
      );
      expect(find.textContaining('Written again'), findsOneWidget);
    });

    testWidgets('a custom category is renamed without orphaning records', (
      tester,
    ) async {
      await store.put('cat', 'cat-my-bread', {'label': 'نان'});
      await store.put('tx', 'tx-1', {
        'type': 'expense',
        'amountRial': 5000,
        'date': DateTime.now().toIso8601String(),
        'category': 'cat-my-bread',
        'note': 'Bread',
      });
      await pumpScreen(tester);
      await tester.tap(find.byTooltip('More of this book'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('expenses-rename-cat-my-bread')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-rename-category')),
        'نان سنگک',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      final raw = await store.get('cat', 'cat-my-bread');
      expect(raw!['label'], 'نان سنگک');
      expect((await store.get('tx', 'tx-1'))!['category'], 'cat-my-bread');
    });

    testWidgets('a search written on another Persian keyboard still finds it', (
      tester,
    ) async {
      await store.put('tx', 'tx-1', {
        'type': 'expense',
        'amountRial': 12000,
        'date': DateTime.now().toIso8601String(),
        'category': 'cat-food',
        'note': 'نانوائي',
      });
      await pumpScreen(tester, locale: const Locale('fa'));
      await tester.tap(find.byTooltip('جست‌وجوی پرداخت‌ها'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-search')),
        'نانوایی',
      );
      await tester.pumpAndSettle();
      expect(find.text('نانوائي'), findsOneWidget);
    });
  });
}
