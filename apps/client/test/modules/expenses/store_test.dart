import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/controller.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/expenses/money.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';
import 'expense_test_store.dart';

/// The controller over a real store: saving, correcting with unknown fields
/// kept, deleting with exact Undo, budgets, templates, the one-tap monthly
/// log, and the two settings a person chooses.
void main() {
  late NexTestHarness harness;
  late ExpensesController controller;
  late NexModuleStore store;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_expctrl_');
    store = NexModuleStore(harness.services, 'expenses');
    controller = ExpensesController(store);
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await harness.dispose();
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('the controller never read the record');
  }

  ExpenseTx payment(String id, {int amountRial = 250000, String? note}) =>
      ExpenseTx(
        id: id,
        type: 'expense',
        amountRial: amountRial,
        date: DateTime(2026, 10, 5, 12),
        categoryId: 'cat-groceries',
        note: note,
      );

  test('a payment is saved as whole rials and read back', () async {
    await controller.saveTx(payment('tx-1'));
    final raw = await store.get('tx', 'tx-1');
    expect(raw!['amountRial'], 250000);
    expect(raw['schema'], 3);
    expect(raw.containsKey('amount'), isFalse);
    expect(raw.containsKey('currency'), isFalse);
    expect(controller.txs.single.amountRial, 250000);
  });

  test('a payment of nothing is refused', () async {
    await expectLater(
      controller.saveTx(payment('tx-0', amountRial: 0)),
      throwsA(isA<StateError>()),
    );
    expect(await store.get('tx', 'tx-0'), isNull);
  });

  test('correcting keeps fields this version does not know', () async {
    await store.put('tx', 'tx-2', {
      'type': 'expense',
      'amountRial': 100000,
      'date': '2026-10-05T12:00:00',
      'category': 'cat-rent',
      'futureField': {'by': 'a later version'},
    });
    await until(() => controller.txById('tx-2') != null);
    final existing = controller.txById('tx-2')!;
    await controller.saveTx(
      ExpenseTx(
        id: 'tx-2',
        type: 'expense',
        amountRial: 120000,
        date: existing.date,
        categoryId: 'cat-rent',
        note: 'October',
      ),
      existing: existing,
    );
    final raw = (await store.get('tx', 'tx-2'))!;
    expect(raw['amountRial'], 120000);
    expect(raw['note'], 'October');
    expect(raw['futureField'], {'by': 'a later version'});
  });

  test('editing a 2.1.x payment converts it once, not twice', () async {
    await store.put('tx', 'tx-old', {
      'type': 'expense',
      'amount': 125000,
      'currency': 'IRR',
      'currency_exponent': 2,
      'date': '2026-10-05T12:00:00',
    });
    await until(() => controller.txById('tx-old') != null);
    final existing = controller.txById('tx-old')!;
    expect(existing.amountRial, 1250);
    await controller.saveTx(
      ExpenseTx(
        id: existing.id,
        type: 'expense',
        amountRial: existing.amountRial,
        date: existing.date,
        note: 'checked',
      ),
      existing: existing,
    );
    final raw = (await store.get('tx', 'tx-old'))!;
    expect(raw['amountRial'], 1250);
    expect(raw.containsKey('amount'), isFalse);
    expect(raw.containsKey('currency'), isFalse);
  });

  test('deleting offers Undo that restores the exact record', () async {
    await store.put('tx', 'tx-3', {
      'type': 'expense',
      'amountRial': 9000,
      'date': '2026-10-05T12:00:00',
      'futureField': 'kept',
    });
    await until(() => controller.txById('tx-3') != null);
    final before = await store.get('tx', 'tx-3');
    await controller.deleteTx('tx-3');
    expect(await store.get('tx', 'tx-3'), isNull);
    await controller.restoreTx(controller.txById('tx-3') ?? payment('tx-3'));
    expect(await store.get('tx', 'tx-3'), before);
  });

  test(
    'a budget is the month it was set for, and moves with its category',
    () async {
      await controller.saveBudget(
        const ExpenseBudget(start: '2026-10-01', amountRial: 2000000),
      );
      expect(controller.budgets.single.amountRial, 2000000);
      final existing = controller.budgetFor('2026-10-01', null)!;
      await controller.saveBudget(
        const ExpenseBudget(
          start: '2026-10-01',
          categoryId: 'cat-groceries',
          amountRial: 1500000,
        ),
        existing: existing,
      );
      expect(controller.budgetFor('2026-10-01', null), isNull);
      expect(
        controller.budgetFor('2026-10-01', 'cat-groceries')!.amountRial,
        1500000,
      );
      await controller.clearBudget('2026-10-01', 'cat-groceries');
      expect(controller.budgets, isEmpty);
    },
  );

  test('a recurring template writes one month, once', () async {
    const template = ExpenseTemplate(
      id: 'tpl-rent',
      label: 'Rent',
      type: 'expense',
      amountRial: 120000000,
      categoryId: 'cat-rent',
      day: 5,
      calendar: 'jalali',
    );
    await controller.saveTemplate(template);
    final dueDay = DateTime(2026, 10, 27);
    final id = await controller.logTemplate(template, dueDay: dueDay);
    expect(id, isNotNull);
    final logged = controller.txById(id!)!;
    expect(logged.amountRial, 120000000);
    expect(logged.templateId, 'tpl-rent');
    expect(
      logged.period,
      monthStartIso(NexModuleMonth.of(dueDay, solar: true)),
    );
    expect(await controller.logTemplate(template, dueDay: dueDay), isNull);
    expect(controller.txs.where((t) => t.templateId == 'tpl-rent').length, 1);
  });

  test('the unit and hiding amounts are remembered', () async {
    expect(controller.unit, ExpenseUnit.toman);
    await controller.rememberUnit(ExpenseUnit.rial);
    await controller.setHideAmounts(true);
    expect(controller.unit, ExpenseUnit.rial);
    expect(controller.hideAmounts, isTrue);
    final again = ExpensesController(store);
    await again.load();
    expect(again.unit, ExpenseUnit.rial);
    expect(again.hideAmounts, isTrue);
    again.dispose();
  });

  test('a read that fails says so instead of showing an empty book', () async {
    final fault = ExpenseFaultStore(harness.services)..failRead = true;
    final failing = ExpensesController(fault);
    await failing.load();
    expect(failing.readFailed, isTrue);
    expect(failing.loading, isFalse);
    failing.dispose();
  });

  test('an interrupted write is rolled back on the next read', () async {
    final fault = ExpenseFaultStore(harness.services)..failAfterTx = true;
    final broken = ExpensesController(fault);
    await broken.load();
    await expectLater(
      broken.saveTx(payment('tx-9')),
      throwsA(isA<StateError>()),
    );
    broken.dispose();
    expect(await store.get('tx', 'tx-9'), isNull);
  });
}
