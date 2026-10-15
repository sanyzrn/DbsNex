import 'package:nex_client/modules/lent_borrowed/loan_dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';

import '../../support/nex_harness.dart';

/// Returns, settlement and its correction, deletion with Undo, and the
/// data outliving the screen.
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_lent_'));
  tearDown(() => harness.dispose());

  Future<NexModuleStore> pumpScreen(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    final store = NexModuleStore(harness.services, 'lent_borrowed');
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoansScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  /// A money loan of 500,000 rials to Ali, due in 7 days, via the sheet.
  Future<String> createLoan(
    WidgetTester tester,
    NexModuleStore store, {
    bool borrowed = false,
    bool item = false,
    String person = 'Ali',
    String amount = '500000',
    String what = 'The blue backpack',
    String dueIn = '7',
  }) async {
    await tester.tap(find.byKey(const ValueKey('loans-new')));
    await tester.pumpAndSettle();
    if (borrowed) {
      await tester.tap(find.byKey(const ValueKey('loan-field-direction')));
      await tester.pumpAndSettle();
    }
    if (item) {
      await tester.tap(find.byKey(const ValueKey('loan-field-kind')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const ValueKey('loan-field-person')),
      person,
    );
    if (item) {
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-what')),
        what,
      );
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-quantity')),
        amount,
      );
    } else {
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-amount')),
        amount,
      );
    }
    if (dueIn.isNotEmpty) {
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-due')),
        dueIn,
      );
    }
    final before = await store.list('loan');
    final save = find.byKey(const ValueKey('loan-save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await settle(tester);
    final loans = await store.list('loan');
    expect(
      loans.length,
      before.length + 1,
      reason: 'the record was really saved',
    );
    return loans.first.id;
  }

  group('returns', () {
    testWidgets('a partial return updates the remainder and the history', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
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
      await settle(tester);

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
      final store = await pumpScreen(tester);
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
      final store = await pumpScreen(tester);
      await createLoan(tester, store);

      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      final settleAll = find.byKey(const ValueKey('loan-mark-settled'));
      await tester.ensureVisible(settleAll);
      await tester.pumpAndSettle();
      await tester.tap(settleAll);
      await settle(tester);

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
      await settle(tester);
      expect(find.text('Return removed'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.text('Returned 500,000 \u2066IRR\u2069'), findsOneWidget);
      expect(find.text('Settled'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('renaming and correcting the total keep the history', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
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
      await settle(tester);

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
      final save = find.byKey(const ValueKey('loan-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await settle(tester);

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
      final store = await pumpScreen(tester);
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
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('loan-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-amount')),
        '300000',
      );
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
  });

  group('deleting with Undo', () {
    testWidgets('Undo restores the record with its whole return history', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
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
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('loan-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete record'));
      await settle(tester);

      expect(await store.list('loan'), isEmpty);
      expect(await store.list('return'), isEmpty);
      expect(find.text('Record deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);

      expect(await store.list('loan'), hasLength(1));
      expect(
        await store.list('return'),
        hasLength(1),
        reason: 'the return history came back too',
      );
      expect(
        find.textContaining('300,000 \u2066IRR\u2069 still out'),
        findsOneWidget,
      );
    });
  });

  group('the screen is a window, not the data', () {
    testWidgets('records survive disposing and re-opening the screen', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await createLoan(tester, store);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      final reopened = NexModuleStore(harness.services, 'lent_borrowed');
      expect(await reopened.list('loan'), hasLength(1));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoansScreen(store: reopened),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ali'), findsOneWidget);
    });

    testWidgets('another module’s store cannot see these records', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await createLoan(tester, store);

      final stranger = NexModuleStore(harness.services, 'habits');
      expect(await stranger.list('loan'), isEmpty);
      expect(await stranger.list('return'), isEmpty);
    });
  });

  testWidgets('renaming an overdue loan keeps both dates and all raw history', (
    tester,
  ) async {
    final store = await pumpScreen(tester);
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
    await settle(tester);
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
    await settle(tester);
    final saved = await store.get('loan', 'dates');
    expect(saved?['issued'], shiftCivilDate(now, -10));
    expect(saved?['due'], shiftCivilDate(now, -1));
    expect(saved?['person'], 'Renamed');
  });

  testWidgets('USD input and partial repayment preserve exact cents', (
    tester,
  ) async {
    final store = await pumpScreen(tester);
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
    await settle(tester);
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
    await settle(tester);
    expect((await store.list('return')).single.body['amount'], 23);
    expect(find.text('1.00 \u2066USD\u2069 still out'), findsOneWidget);
  });
}
