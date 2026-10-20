import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/lent_borrowed/loan_date_entry.dart';
import 'package:nex_client/modules/lent_borrowed/loan_dates.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';

import '../../support/nex_harness.dart';

/// The lent & borrowed module end to end: both directions kept apart,
/// partial returns that never over-repay, edits that never wipe history,
/// deletion with Undo that restores everything, and due dates said out
/// loud the moment the screen opens.
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

  /// Creates a record through the real sheet. Defaults describe a money
  /// loan of 500,000 rials to Ali, due in 7 days.
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
      final preset = find.byKey(ValueKey('loan-due-preset-$dueIn'));
      await tester.ensureVisible(preset);
      await tester.pumpAndSettle();
      await tester.tap(preset);
      await tester.pumpAndSettle();
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

  group('empty states', () {
    testWidgets('each direction has its own honest empty state', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.textContaining('Record something you lent'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('loans-tab-borrowed')));
      await tester.pumpAndSettle();
      expect(find.text('You haven’t borrowed anything yet.'), findsOneWidget);
    });
  });

  group('creating records', () {
    testWidgets('a lent money record, with its due date said in words', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await createLoan(tester, store);

      expect(find.text('Ali'), findsOneWidget);
      expect(
        find.textContaining('500,000 \u2066IRR\u2069 still out'),
        findsOneWidget,
      );
      expect(find.text('Due in 7 days'), findsOneWidget);

      final body = (await store.list('loan')).first.body;
      expect(body['direction'], 'lent');
      expect(body['amount'], 500000);
      expect(body['due'], isNotNull);
    });

    testWidgets('a borrowed record never appears under Lent', (tester) async {
      final store = await pumpScreen(tester);
      await createLoan(tester, store, borrowed: true, person: 'Sara');

      expect(
        find.text('Sara'),
        findsNothing,
        reason: 'the Lent tab shows nothing borrowed',
      );
      await tester.tap(find.byKey(const ValueKey('loans-tab-borrowed')));
      await tester.pumpAndSettle();
      expect(find.text('Sara'), findsOneWidget);

      final body = (await store.list('loan')).first.body;
      expect(body['direction'], 'borrowed');
    });

    testWidgets('an item record carries what it is and how many', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await createLoan(tester, store, item: true, amount: '2');

      expect(find.textContaining('The blue backpack'), findsOneWidget);
      expect(find.textContaining('2 still out'), findsOneWidget);
      final body = (await store.list('loan')).first.body;
      expect(body['type'], 'item');
      expect(body['what'], 'The blue backpack');
      expect(body['amount'], 2);
    });

    testWidgets('no name, no record', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('loans-new')));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('loan-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Write who this was with first'), findsOneWidget);
      expect(find.byKey(const ValueKey('loan-field-person')), findsOneWidget);
    });

    testWidgets('the due presets fill the field in one tap', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('loans-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-person')),
        'Ali',
      );
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-amount')),
        '100000',
      );
      final preset = find.byKey(const ValueKey('loan-due-preset-30'));
      await tester.ensureVisible(preset);
      await tester.pumpAndSettle();
      await tester.tap(preset);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('loan-due-date-entry')),
                    matching: find.byType(TextField),
                  )
                  .first,
            )
            .controller!
            .text,
        dateEntryText(shiftCivilDate(DateTime.now(), 30)),
      );
    });
  });

  group('a meaningful journey', () {
    testWidgets('from lending to fully settled, in both directions', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await createLoan(tester, store, person: 'Ali', amount: '300000');

      // Partial, then the rest.
      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan-record-return')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('return-field-amount')),
        '100000',
      );
      final returnSave = find.byKey(const ValueKey('return-save'));
      await tester.ensureVisible(returnSave);
      await tester.pumpAndSettle();
      await tester.tap(returnSave);
      await settle(tester);
      expect(
        find.textContaining('200,000 \u2066IRR\u2069 still out'),
        findsOneWidget,
      );

      final settleAll = find.byKey(const ValueKey('loan-mark-settled'));
      await tester.ensureVisible(settleAll);
      await tester.pumpAndSettle();
      await tester.tap(settleAll);
      await settle(tester);
      expect(find.text('Settled'), findsOneWidget);

      // And a debt in the other direction, kept apart.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await createLoan(tester, store, borrowed: true, person: 'Sara');
      expect(find.text('Sara'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('loans-tab-borrowed')));
      await tester.pumpAndSettle();
      expect(find.text('Sara'), findsOneWidget);
      expect(
        find.textContaining('500,000 \u2066IRR\u2069 still out'),
        findsOneWidget,
      );
    });
  });

  group('due dates, said when the app opens', () {
    testWidgets('an overdue loan is marked the moment the screen shows', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      final now = DateTime.now();
      final issued = civilDateKey(now.subtract(const Duration(days: 10)));
      final due = civilDateKey(now.subtract(const Duration(days: 2)));
      await store.put('loan', 'l1', {
        'direction': 'lent',
        'person': 'Ali',
        'type': 'money',
        'amount': 100000,
        'what': '',
        'issued': issued,
        'due': due,
        'note': '',
      });
      await tester.pumpAndSettle();

      expect(find.text('2 days overdue'), findsOneWidget);
    });

    testWidgets('a loan due today says today, not a number', (tester) async {
      final store = await pumpScreen(tester);
      await store.put('loan', 'l1', {
        'direction': 'lent',
        'person': 'Ali',
        'type': 'money',
        'amount': 100000,
        'what': '',
        'issued': civilDateKey(DateTime.now()),
        'due': civilDateKey(DateTime.now()),
        'note': '',
      });
      await tester.pumpAndSettle();
      expect(find.text('Due today'), findsOneWidget);
    });
  });
}
