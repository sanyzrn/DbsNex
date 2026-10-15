import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/controller.dart';
import 'package:nex_client/modules/expenses/logic.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

/// The controller over a real store: writes land, reloads are ordered,
/// edits move months, deletions restore exactly, and no other module
/// can see any of it.
void main() {
  late NexTestHarness harness;
  late NexModuleStore store;
  late ExpensesController controller;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_exp_');
    store = NexModuleStore(harness.services, 'expenses');
    controller = ExpensesController(store);
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await harness.dispose();
  });

  ExpenseTx expense(
    String id,
    DateTime date, {
    int amount = 100000,
    String category = 'cat-food',
    String currency = 'IRR',
  }) => ExpenseTx(
    id: id,
    type: 'expense',
    amount: amount,
    currency: currency,
    date: date,
    categoryId: category,
  );

  test(
    'a saved transaction is read back exactly, newest saved first',
    () async {
      await controller.saveTx(expense('tx-a', DateTime(2026, 10, 1)));
      await controller.saveTx(expense('tx-b', DateTime(2026, 10, 2)));
      expect(controller.txs, hasLength(2));
      expect(controller.txs.first.id, 'tx-b'); // list() is newest-saved first
      expect(controller.txs.first.amount, 100000);
      expect(controller.txs.first.categoryId, 'cat-food');
    },
  );

  test(
    'editing a record across a monthly boundary moves the aggregates',
    () async {
      final original = expense('tx-move', DateTime(2026, 10, 31, 23, 30));
      await controller.saveTx(original);
      expect(txsInMonth(controller.txs, '2026-10'), hasLength(1));
      expect(txsInMonth(controller.txs, '2026-11'), isEmpty);

      final moved = ExpenseTx(
        id: 'tx-move',
        type: 'expense',
        amount: original.amount,
        currency: 'IRR',
        date: DateTime(2026, 11, 1, 0, 15),
        categoryId: 'cat-food',
      );
      await controller.saveTx(moved);
      expect(txsInMonth(controller.txs, '2026-10'), isEmpty);
      expect(txsInMonth(controller.txs, '2026-11'), hasLength(1));

      // January/December, the other boundary direction.
      await controller.saveTx(
        ExpenseTx(
          id: 'tx-dec',
          type: 'expense',
          amount: 5,
          currency: 'IRR',
          date: DateTime(2026, 12, 31, 23, 59),
          categoryId: 'cat-food',
        ),
      );
      await controller.saveTx(
        ExpenseTx(
          id: 'tx-dec',
          type: 'expense',
          amount: 5,
          currency: 'IRR',
          date: DateTime(2027, 1, 1),
          categoryId: 'cat-food',
        ),
      );
      expect(txsInMonth(controller.txs, '2026-12'), isEmpty);
      expect(txsInMonth(controller.txs, '2027-01'), hasLength(1));
    },
  );

  test('deletion and Undo restore the exact body', () async {
    final original = expense('tx-undo', DateTime(2026, 10, 5), amount: 4242);
    await controller.saveTx(original);
    await controller.deleteTx('tx-undo');
    expect(controller.txs, isEmpty);
    await controller.restoreTx(original);
    expect(controller.txs, hasLength(1));
    expect(controller.txs.first.amount, 4242);
    expect(controller.txs.first.id, 'tx-undo');
  });

  test(
    'budgets: deterministic id, replace, clear, per month and currency',
    () async {
      const budget = ExpenseBudget(
        month: '2026-10',
        currency: 'IRR',
        amount: 500000,
        categoryId: 'cat-food',
      );
      await controller.saveBudget(budget);
      expect(controller.budgets, hasLength(1));
      expect(
        controller.budgetFor('2026-10', 'cat-food', 'IRR')!.amount,
        500000,
      );

      // Same key replaces, never duplicates.
      await controller.saveBudget(
        const ExpenseBudget(
          month: '2026-10',
          currency: 'IRR',
          amount: 600000,
          categoryId: 'cat-food',
        ),
      );
      expect(controller.budgets, hasLength(1));
      expect(controller.budgets.first.amount, 600000);

      // Another month or currency is another budget.
      await controller.saveBudget(
        const ExpenseBudget(month: '2026-11', currency: 'IRR', amount: 1),
      );
      await controller.saveBudget(
        const ExpenseBudget(month: '2026-10', currency: 'USD', amount: 2),
      );
      expect(controller.budgets, hasLength(3));
      expect(controller.budgetFor('2026-10', null, 'USD')!.amount, 2);

      await controller.clearBudget('2026-10', 'cat-food', 'IRR');
      expect(controller.budgets, hasLength(2));
      expect(controller.budgetFor('2026-10', 'cat-food', 'IRR'), isNull);

      // A budget change never erases transactions.
      expect(controller.txs, isEmpty);
    },
  );

  test(
    'categories: add, read, delete; defaults are synthesized, not stored',
    () async {
      expect(controller.customCategories, isEmpty);
      await controller.addCategory('Coffee');
      expect(controller.customCategories, hasLength(1));
      expect(controller.customCategories.first.label, 'Coffee');
      await controller.addCategory('   '); // blank is refused
      expect(controller.customCategories, hasLength(1));
      await controller.deleteCategory(controller.customCategories.first);
      expect(controller.customCategories, isEmpty);
      // And nothing was ever written for the defaults.
      expect(await store.list('cat'), isEmpty);
    },
  );

  test('templates: save, list, delete', () async {
    await controller.saveTemplate(
      const ExpenseTemplate(
        id: '',
        label: 'Rent',
        type: 'expense',
        amount: 2500000,
        currency: 'IRR',
        categoryId: 'cat-home',
      ),
    );
    expect(controller.templates, hasLength(1));
    expect(controller.templates.first.label, 'Rent');
    expect(controller.templates.first.id, isNotEmpty);
    await controller.deleteTemplate(controller.templates.first.id);
    expect(controller.templates, isEmpty);
  });

  test('editor defaults are remembered and rial stays the default', () async {
    expect(controller.preferredCurrencyCode, 'IRR');
    expect(controller.preferredIrrUnit, 'rial');
    await controller.rememberEditorDefaults(
      currencyCode: 'USD',
      irrUnit: 'rial',
    );
    expect(controller.preferredCurrencyCode, 'USD');
    await controller.rememberEditorDefaults(
      currencyCode: 'IRR',
      irrUnit: 'toman',
    );
    expect(controller.preferredIrrUnit, 'toman');
  });

  test(
    'records persist across a fresh controller, as after reopening',
    () async {
      await controller.saveTx(expense('tx-persist', DateTime(2026, 10, 2)));
      await controller.addCategory('Books');
      await controller.saveBudget(
        const ExpenseBudget(month: '2026-10', currency: 'IRR', amount: 5),
      );
      await controller.saveTemplate(
        const ExpenseTemplate(
          id: '',
          label: 'Bus',
          type: 'expense',
          amount: 1000,
          currency: 'IRR',
        ),
      );

      final reopened = ExpensesController(store);
      await reopened.load();
      expect(reopened.txs, hasLength(1));
      expect(reopened.customCategories.first.label, 'Books');
      expect(reopened.budgets, hasLength(1));
      expect(reopened.templates, hasLength(1));
      reopened.dispose();
    },
  );

  test('no other module sees these records', () async {
    await controller.saveTx(expense('tx-isolated', DateTime(2026, 10, 2)));
    final other = NexModuleStore(harness.services, 'maintenance');
    expect(await other.list('tx'), isEmpty);
    expect(
      await harness.services.moduleRecords('expenses', 'tx'),
      hasLength(1),
    );
    expect(await harness.services.moduleRecords('other', 'tx'), isEmpty);
  });

  test('ids from the store are unique and prefixed', () {
    final a = controller.newTxId();
    final b = controller.newTxId();
    expect(a, isNot(b));
    expect(a, startsWith('tx-'));
  });
}
