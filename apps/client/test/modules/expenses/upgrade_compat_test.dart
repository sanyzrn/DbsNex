import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/controller.dart';
import 'package:nex_client/modules/expenses/expenses_screen.dart';
import 'package:nex_client/modules/expenses/expenses_summary.dart';
import 'package:nex_client/modules/expenses/logic.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/expenses/money.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// The upgrade's promise: records exactly as 2.1.x wrote them — a currency,
/// an amount in its minor units, a Gregorian month key, a template, extra
/// fields this version has never heard of — still open, still mean the same
/// money, and are still all there.
void main() {
  late NexTestHarness harness;
  late NexModuleStore store;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_expcompat_');
    store = NexModuleStore(harness.services, 'expenses');
    await store.put('tx', 'tx-rial', {
      'type': 'expense',
      'amount': 125000,
      'currency': 'IRR',
      'currency_code': 'IRR',
      'currency_exponent': 2,
      'date': '2026-11-05T12:30:00',
      'category': 'cat-food',
      'note': 'نان',
      'merchant': 'نانوایی',
      'futureField': {'by': 'a later version'},
      'schema': 2,
    });
    await store.put('tx', 'tx-dollar', {
      'type': 'expense',
      'amount': 1250,
      'currency': 'USD',
      'currency_code': 'USD',
      'currency_exponent': 2,
      'date': '2026-11-06T09:00:00',
      'category': 'cat-food',
      'schema': 2,
    });
    await store.put('budget', 'budget-2026-11-cat-food-IRR', {
      'month': '2026-11',
      'currency': 'IRR',
      'amount': 500000000,
      'category': 'cat-food',
      'schema': 2,
    });
    await store.put('tpl', 'tpl-net', {
      'label': 'Internet',
      'type': 'expense',
      'amount': 4500000,
      'currency': 'IRR',
      'category': 'cat-bills',
      'schema': 2,
    });
  });

  tearDown(() async => harness.dispose());

  test('every old record opens; none is hidden', () async {
    final controller = ExpensesController(store);
    await controller.load();
    expect(controller.txs.length, 2);
    expect(controller.budgets.length, 1);
    expect(controller.templates.length, 1);
    final rial = controller.txById('tx-rial')!;
    expect(rial.valid, isTrue);
    expect(rial.amountRial, 1250);
    expect(rial.note, 'نان');
    final dollar = controller.txById('tx-dollar')!;
    expect(dollar.valid, isFalse, reason: 'no exchange rate is invented');
    controller.dispose();
  });

  test('the money keeps its meaning: whole rials, converted once', () async {
    final controller = ExpensesController(store);
    await controller.load();
    final totals = expenseTotals(controller.txs);
    expect(totals.expense, BigInt.from(1250));
    final budget = controller.budgets.single;
    expect(budget.start, '2026-11-01');
    expect(budget.amountRial, 5000000);
    expect(controller.templates.single.amountRial, 45000);
    controller.dispose();
  });

  test(
    'a legacy budget is the month it named, and shows its standing',
    () async {
      final controller = ExpensesController(store);
      await controller.load();
      final month = NexModuleMonth(false, 2026, 11);
      final statuses = expenseBudgetStatuses(
        controller.budgets,
        month,
        controller.txs,
      );
      expect(statuses.single.spent, BigInt.from(1250));
      expect(statuses.single.budget.categoryId, 'cat-food');
      controller.dispose();
    },
  );

  testWidgets('the screen shows the old book, flagged where it needs repair', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ExpensesScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    // The rial payment reads in Persian, in tomans, as it was entered.
    expect(find.text('۱۲۵ تومان'), findsWidgets);
    // The dollar one is visible as an incomplete record, not silently gone.
    expect(find.text('ثبت ناقص'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('correcting an old payment keeps the fields it does not know', () async {
    final controller = ExpensesController(store);
    await controller.load();
    final existing = controller.txById('tx-rial')!;
    await controller.saveTx(
      ExpenseTx(
        id: existing.id,
        type: 'expense',
        amountRial: 1500,
        date: existing.date,
        categoryId: existing.categoryId,
        note: 'نان سنگک',
        merchant: existing.merchant,
      ),
      existing: existing,
    );
    final raw = (await store.get('tx', 'tx-rial'))!;
    expect(raw['amountRial'], 1500);
    expect(raw['merchant'], 'نانوایی');
    expect(raw['futureField'], {'by': 'a later version'});
    expect(raw['note'], 'نان سنگک');
    expect(raw.containsKey('amount'), isFalse);
    expect(raw.containsKey('currency'), isFalse);
    controller.dispose();
  });

  test('an old record still gets its line in the shared summary', () async {
    final rows = await store.list('tx');
    final rial = rows.firstWhere((r) => r.id == 'tx-rial');
    final line = summarize(rial)!;
    expect(line.title, 'نان');
    expect(line.private, isTrue);
    expect(
      formatExpenseAmount(1250, ExpenseUnit.toman, persian: false),
      '125 tomans',
    );
  });
}
