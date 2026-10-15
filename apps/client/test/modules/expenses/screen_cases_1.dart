part of 'screen_test.dart';

void _screenCases1() {
  group('the overview', () {
    testWidgets('empty state says what to do, with the button to do it', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Nothing written down yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-add')), findsOneWidget);
      // The empty state's own action and the FAB both say it.
      expect(find.text('Add a payment'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      expect(find.text('New expense'), findsOneWidget);
    });

    testWidgets('an expense adds, totals, and lands in the breakdown', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '1250', note: 'corner shop');
      expect(find.text('corner shop'), findsOneWidget);
      expect(find.text('1,250 IRR'), findsAtLeast(1));
      expect(find.text('Expenses'), findsAtLeast(1));
      expect(find.text('This month'), findsOneWidget);
      // No category was picked, so it lands in Other — with its
      // integer percent beside it.
      expect(find.text('Other'), findsAtLeast(1));
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('income and net, without alarm when negative', (tester) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '5000');
      await addPayment(tester, amount: '2000', income: true);
      expect(find.text('5,000 IRR'), findsAtLeast(1));
      expect(find.text('+2,000 IRR'), findsOneWidget);
      expect(find.text('Net'), findsOneWidget);
      expect(find.text('−3,000 IRR'), findsOneWidget);
      expect(
        find.text('Spent more than you entered as income'),
        findsOneWidget,
      );
    });

    testWidgets('currencies are never combined', (tester) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '1000');
      // A second currency: pick USD in the picker sheet.
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '9.99',
      );
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      expect(find.text('9.99 USD'), findsAtLeast(1));
      expect(find.text('1,000 IRR'), findsAtLeast(1));
      expect(
        find.text('Totals per currency — currencies are never combined'),
        findsOneWidget,
      );
    });

    testWidgets('toman entry is labelled and converts exactly', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tomans'));
      await tester.pumpAndSettle();
      expect(find.text('1 toman = 10 rials'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '12.5',
      );
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      // 12.5 toman is 125 rials, shown in rials.
      expect(find.text('125 IRR'), findsAtLeast(1));
    });

    testWidgets('junk amounts are refused with words, not silence', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      // Letters and double separators both parse to nothing and say so.
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        'abc',
      );
      await tester.pumpAndSettle();
      expect(find.text('Numbers only — no signs or letters'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '1.2.3',
      );
      await tester.pumpAndSettle();
      expect(find.text('Numbers only — no signs or letters'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      // Still on the editor: nothing was saved.
      expect(find.text('New expense'), findsOneWidget);
      // Zero says why only once Save has been refused.
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '0',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      expect(find.text('The amount cannot be zero'), findsOneWidget);
    });
  });

  group('records, editing and deletion', () {
    testWidgets('edit changes the amount and the totals follow', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '1000', note: 'first');
      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();
      expect(find.text('Edit expense'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '3000',
      );
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      expect(find.text('3,000 IRR'), findsAtLeast(1));
      expect(find.text('1,000 IRR'), findsNothing);
    });

    testWidgets('delete asks, then Undo restores exactly', (tester) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '4242', note: 'gone soon');
      await tester.tap(find.text('gone soon'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this record?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Deleted'), findsOneWidget);
      expect(find.text('gone soon'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('gone soon'), findsOneWidget);
      expect(find.text('4,242 IRR'), findsAtLeast(1));
    });

    testWidgets('the editor guards unsaved work on back', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '500',
      );
      await tester.pumpAndSettle();
      // The system's back, with something typed: the discard question
      // appears rather than losing the work.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard this entry?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      // Still editing; the amount is still there.
      expect(find.text('New expense'), findsOneWidget);
      // Discarding explicitly: the amount still counts as work.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('New expense'), findsNothing);
      expect(find.text('Nothing written down yet'), findsOneWidget);
    });
  });

  group('months, filters and search', () {
    testWidgets('month navigation walks and comes back', (tester) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '1000');
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('Last month'), findsOneWidget);
      expect(find.text('Nothing spent in this view'), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('1,000 IRR'), findsAtLeast(1));
    });

    testWidgets('all time keeps every record', (tester) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '1000');
      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      expect(find.text('All time'), findsAtLeast(1));
      expect(find.text('1,000 IRR'), findsAtLeast(1));
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(find.text('This month'), findsOneWidget);
    });

    testWidgets('the category chip filters, and All clears', (tester) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '1000', note: 'bread');
      // Change category to Transport through the picker.
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '200',
      );
      await tester.tap(find.byKey(const ValueKey('expenses-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transport').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      // Filter to Other (the first payment chose no category):
      // only bread remains.
      await tester.tap(find.text('Other').first);
      await tester.pumpAndSettle();
      expect(find.text('bread'), findsOneWidget);
      expect(find.text('1,000 IRR'), findsAtLeast(1));
      final transport = (await store.list(
        'tx',
      )).firstWhere((r) => r.body['category'] == 'cat-transport');
      expect(find.byKey(ValueKey('expenses-tx-${transport.id}')), findsNothing);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('expenses-tx-${transport.id}')),
        findsOneWidget,
      );
    });

    testWidgets('search finds notes and says when nothing does', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '1000', note: 'bread');
      await addPayment(tester, amount: '2000', note: 'bus ticket');
      await tester.tap(find.byTooltip('Search payments'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-search')),
        'bus',
      );
      await tester.pumpAndSettle();
      expect(find.text('bus ticket'), findsOneWidget);
      expect(find.text('bread'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('expenses-search')),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches'), findsOneWidget);
    });
  });
}
