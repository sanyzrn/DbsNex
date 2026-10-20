import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loan_dates.dart';

import '../../support/nex_harness.dart';
import 'loans_test_tools.dart';

/// Returns, settlement and its correction, and the dates of an edited loan
/// staying exactly where they were.
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_lent_'));
  tearDown(() => harness.dispose());

  group('returns', () {
    testWidgets('a partial return updates the remainder and the history', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      final id = await createLoan(tester, store);

      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('return-field-amount')),
        '200000',
      );
      final save = find.byKey(const ValueKey('return-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await settleLoans(tester);

      expect(
        find.textContaining('300,000 \u2066IRR\u2069 still out'),
        findsOneWidget,
      );
      expect(find.text('Returned 200,000 \u2066IRR\u2069'), findsOneWidget);
      final returns = await store.list('return');
      expect(returns, hasLength(1));
      expect(returns.first.body['loan'], id);
    });

    testWidgets('over-repayment is refused, exactly at one over', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);

      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('return-field-amount')),
        '500001',
      );
      final save = find.byKey(const ValueKey('return-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text('That is more than is still outstanding'),
        findsOneWidget,
      );
      expect(await store.list('return'), isEmpty);
    });

    testWidgets('marking fully settled, then correcting it', (tester) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);

      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      final settleAll = find.byKey(const ValueKey('loan-mark-settled'));
      await tester.ensureVisible(settleAll);
      await tester.pumpAndSettle();
      await tester.tap(settleAll);
      await settleLoans(tester);

      expect(
        find.textContaining('500,000 \u2066IRR\u2069 still out'),
        findsNothing,
      );
      expect(find.text('Returned 500,000 \u2066IRR\u2069'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.text('Settled'),
        findsWidgets,
        reason: 'the settled section heading and the row itself',
      );

      // The settlement was exactly a return — taking it back undoes it.
      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      final delete = find.byIcon(Icons.delete_outline);
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await settleLoans(tester);
      expect(find.text('Return removed'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settleLoans(tester);
      expect(find.text('Returned 500,000 \u2066IRR\u2069'), findsOneWidget);
      expect(find.text('Settled'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('renaming and correcting the total keep the history', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);

      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('return-field-amount')),
        '200000',
      );
      final returnSave = find.byKey(const ValueKey('return-save'));
      await tester.ensureVisible(returnSave);
      await tester.pumpAndSettle();
      await tester.tap(returnSave);
      await settleLoans(tester);

      await tester.tap(find.byKey(const ValueKey('loan-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-person')),
        'Ali Rezaei',
      );
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-amount')),
        '600000',
      );
      // Let the focused amount field finish its own scroll-into-view before
      // the test scrolls to the save button; otherwise the caret's scroll
      // races ensureVisible and drags the button back below the fold.
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('loan-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await settleLoans(tester);

      expect(find.text('Ali Rezaei'), findsOneWidget);
      expect(
        find.textContaining('400,000 \u2066IRR\u2069 still out'),
        findsOneWidget,
      );
      expect(
        await store.list('return'),
        hasLength(1),
        reason: 'the edit never wiped the return history',
      );
    });

    testWidgets('a total below what already came back is refused', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);

      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('return-field-amount')),
        '400000',
      );
      final returnSave = find.byKey(const ValueKey('return-save'));
      await tester.ensureVisible(returnSave);
      await tester.pumpAndSettle();
      await tester.tap(returnSave);
      await settleLoans(tester);

      await tester.tap(find.byKey(const ValueKey('loan-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-amount')),
        '300000',
      );
      // Same caret-scroll settle as in the renaming test above.
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('loan-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text('The new total is less than what has already come back'),
        findsOneWidget,
      );
      expect((await store.list('loan')).first.body['amount'], 500000);
    });

    testWidgets('a typed date before the issue date is refused', (
      tester,
    ) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await createLoan(tester, store);

      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-due')),
        shiftCivilDate(DateTime.now(), -3),
      );
      final save = find.byKey(const ValueKey('loan-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text('Due date cannot be before the issue date'),
        findsOneWidget,
      );
      expect(await store.list('loan'), hasLength(1));
    });
  });

  testWidgets('renaming an overdue loan keeps both dates and all raw history', (
    tester,
  ) async {
    final store = await pumpLoansScreen(tester, harness: harness);
    final now = DateTime.now();
    await store.put('loan', 'dates', {
      'person': 'Old name',
      'direction': 'lent',
      'type': 'money',
      'amount': 500000,
      'issued': shiftCivilDate(now, -10),
      'due': shiftCivilDate(now, -1),
      'note': '',
    });
    await settleLoans(tester);
    await tester.tap(find.text('Old name'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('loan-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('loan-field-person')),
      'Renamed',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('loan-save')));
    await tester.tap(find.byKey(const ValueKey('loan-save')));
    await settleLoans(tester);
    final saved = await store.get('loan', 'dates');
    expect(saved?['issued'], shiftCivilDate(now, -10));
    expect(saved?['due'], shiftCivilDate(now, -1));
    expect(saved?['person'], 'Renamed');
  });

  testWidgets(
    'a legacy loan dated before the typed range keeps its exact dates',
    (tester) async {
      final store = await pumpLoansScreen(tester, harness: harness);
      await store.put('loan', 'ancient', {
        'person': 'Museum piece',
        'direction': 'lent',
        'type': 'money',
        'amount': 1000,
        'issued': '1500-06-15',
        'due': '1500-07-01',
        'note': '',
      });
      await settleLoans(tester);
      await tester.tap(find.text('Museum piece'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-edit')));
      await tester.pumpAndSettle();
      expect(find.text('1500/06/15'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-person')),
        'Renamed anyway',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('loan-save')));
      await tester.tap(find.byKey(const ValueKey('loan-save')));
      await settleLoans(tester);
      final saved = await store.get('loan', 'ancient');
      expect(saved?['issued'], '1500-06-15');
      expect(saved?['due'], '1500-07-01');
      expect(saved?['person'], 'Renamed anyway');
    },
  );

  testWidgets('USD input and partial repayment preserve exact cents', (
    tester,
  ) async {
    final store = await pumpLoansScreen(tester, harness: harness);
    await tester.tap(find.byKey(const ValueKey('loans-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('loan-field-person')),
      'Foreign loan',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('loan-field-currency')),
    );
    await tester.tap(find.byKey(const ValueKey('loan-field-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('loan-field-amount')),
      '1.23',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('loan-save')));
    await tester.tap(find.byKey(const ValueKey('loan-save')));
    await settleLoans(tester);
    final loan = (await store.list('loan')).single;
    expect(loan.body['currency'], 'USD');
    expect(loan.body['amount'], 123);
    await tester.tap(find.text('Foreign loan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('loan-record-return')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('return-field-amount')),
      '0.23',
    );
    await tester.tap(find.byKey(const ValueKey('return-save')));
    await settleLoans(tester);
    expect((await store.list('return')).single.body['amount'], 23);
    expect(find.text('1.00 \u2066USD\u2069 still out'), findsOneWidget);
  });
}
