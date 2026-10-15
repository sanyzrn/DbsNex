import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/controller.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'expense_test_store.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late ExpenseFaultStore store;
  late ExpensesController controller;
  setUp(() async {
    h = await NexTestHarness.create(name: 'expense_reliability_');
    store = ExpenseFaultStore(h.services);
    controller = ExpensesController(store);
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    await h.dispose();
  });
  ExpenseTx tx({int amount = 100, String? note}) => ExpenseTx(
    id: 'r',
    type: 'expense',
    amount: amount,
    currency: 'USD',
    date: DateTime(2026, 10, 14),
    note: note,
  );
  test(
    'a failed read is visible and Retry does not replace saved values',
    () async {
      await controller.saveTx(tx());
      store.failRead = true;
      await controller.load();
      expect(controller.readFailed, isTrue);
      expect(controller.txs.single.amount, 100);
      store.failRead = false;
      await controller.load();
      expect(controller.readFailed, isFalse);
    },
  );
  test(
    'failure after a put rolls back and same-ID retry makes one payment',
    () async {
      store.failAfterTx = true;
      await expectLater(controller.saveTx(tx()), throwsStateError);
      expect(await store.get('tx', 'r'), isNull);
      await controller.saveTx(tx());
      expect((await store.list('tx')).length, 1);
      expect(await store.list('operation'), isEmpty);
    },
  );
  test(
    'fresh edits preserve a concurrently corrected amount and unknown fields',
    () async {
      await store.put('tx', 'r', {
        ...tx(note: 'Old').toBody(),
        'future': {'x': true},
      });
      final existing = ExpenseTx.fromBody('r', (await store.get('tx', 'r'))!);
      await store.put('tx', 'r', {...existing.source!, 'amount': 999});
      await controller.saveTx(tx(note: 'Typed'), existing: existing);
      final body = (await store.get('tx', 'r'))!;
      expect(body['amount'], 999);
      expect(body['note'], 'Typed');
      expect(body['future'], {'x': true});
      await store.delete('tx', 'r');
      await expectLater(
        controller.saveTx(tx(note: 'Lost'), existing: existing),
        throwsStateError,
      );
      expect(await store.get('tx', 'r'), isNull);
    },
  );
  test(
    'category Undo restores identity used by transactions and budgets',
    () async {
      await controller.addCategory('Coffee', id: 'cat-stable');
      await store.put('cat', 'cat-stable', {'label': 'Coffee', 'future': 9});
      final category = ExpenseCategory(id: 'cat-stable', label: 'Coffee');
      await store.put('tx', 'r', {...tx().toBody(), 'category': 'cat-stable'});
      await controller.saveBudget(
        const ExpenseBudget(
          month: '2026-10',
          currency: 'USD',
          amount: 100,
          categoryId: 'cat-stable',
        ),
      );
      await controller.deleteCategory(category);
      await controller.restoreCategory(category);
      expect(await store.get('cat', 'cat-stable'), {
        'label': 'Coffee',
        'future': 9,
      });
      expect((await store.get('tx', 'r'))!['category'], 'cat-stable');
      expect(controller.budgets.single.categoryId, 'cat-stable');
      expect(await store.list('cat'), hasLength(1));
    },
  );
  test(
    'transaction delete Undo preserves the exact raw body and related draft',
    () async {
      final raw = {
        ...tx().toBody(),
        'unknown': [1, 2],
        'note': '',
      };
      final draft = {
        'v': 1,
        'fields': {'amount': 'invalid'},
      };
      await store.put('tx', 'r', raw);
      await store.put('draft', 'tx:r', draft);
      await controller.deleteTx('r');
      expect(await store.get('draft', 'tx:r'), isNull);
      await controller.restoreTx(tx());
      expect(await store.get('tx', 'r'), raw);
      expect(await store.get('draft', 'tx:r'), draft);
      await controller.deleteTx('r');
      await store.put('tx', 'r', tx(amount: 200).toBody());
      await expectLater(controller.restoreTx(tx()), throwsStateError);
      expect((await store.get('tx', 'r'))!['amount'], 200);
    },
  );
  test(
    'moving a budget replaces its original identity without touching payments',
    () async {
      final original = ExpenseBudget(
        month: '2026-10',
        currency: 'USD',
        amount: 100,
      );
      await controller.saveTx(tx());
      await controller.saveBudget(original);
      await controller.saveBudget(
        const ExpenseBudget(month: '2026-10', currency: 'JPY', amount: 50),
        existing: original,
      );
      expect(controller.budgets, hasLength(1));
      expect(controller.budgets.single.currency, 'JPY');
      expect(controller.txs.single.currency, 'USD');
    },
  );
  test(
    'a text correction preserves a fresh currency and its exponent',
    () async {
      await store.put('tx', 'r', tx(note: 'Old').toBody());
      final old = ExpenseTx.fromBody('r', (await store.get('tx', 'r'))!);
      await store.put('tx', 'r', {
        ...old.source!,
        'currency': 'JPY',
        'currency_code': 'JPY',
        'currency_exponent': 0,
        'amount': 999,
      });
      await controller.saveTx(tx(note: 'Typed'), existing: old);
      final raw = (await store.get('tx', 'r'))!;
      expect(raw['currency'], 'JPY');
      expect(raw['currency_exponent'], 0);
      expect(raw['amount'], 999);
      expect(raw['note'], 'Typed');
      expect(ExpenseTx.fromBody('r', raw).valid, isTrue);
    },
  );
}
