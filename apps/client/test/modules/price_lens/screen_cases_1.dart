part of 'screen_test.dart';

void _screenCases1() {
  group('the calculator', () {
    testWidgets('empty state says what to do, and the editor opens from it', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Add an offer to start comparing'), findsOneWidget);
      expect(
        find.text('No retailer prices are known — only what you type'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('lens-add')));
      await tester.pumpAndSettle();
      expect(find.text('New offer'), findsOneWidget);
      expect(find.text('Total bundle price before discount'), findsOneWidget);
      expect(find.text('Quantity in one package'), findsOneWidget);
    });

    testWidgets('2 × 500ml against 1L: the exact answer, best and savings', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOption(
        tester,
        label: 'Two 500ml',
        price: '100',
        quantity: '500',
        unitKey: 'ml',
        count: '2',
      );
      await addOption(
        tester,
        label: 'One litre',
        price: '120',
        quantity: '1',
        unitKey: 'l',
      );
      expect(find.text('Cheapest per L'), findsOneWidget);
      expect(find.text('Two 500ml · 100 IRR per L'), findsOneWidget);
      expect(find.text('One litre · 120 IRR per L'), findsOneWidget);
      expect(find.text('20 IRR more than the cheapest'), findsOneWidget);
      expect(find.text('Cheapest'), findsOneWidget);
      // The multi-pack card says what it holds; no paid/received line
      // was typed, so none is implied.
      expect(find.textContaining('500 ml × 2'), findsOneWidget);
      expect(find.text('paid 2, received 3'), findsNothing);
    });

    testWidgets('750g against 1kg: the cheaper-looking bag is dearer', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOption(
        tester,
        label: 'Bag 750g',
        price: '90',
        quantity: '750',
        unitKey: 'g',
      );
      await addOption(tester, label: 'Bag 1kg', price: '115', quantity: '1');
      expect(find.text('Cheapest per kg'), findsOneWidget);
      expect(find.text('Bag 750g · 120 IRR per kg'), findsOneWidget);
      expect(find.text('Bag 1kg · 115 IRR per kg'), findsOneWidget);
      expect(find.text('5 IRR more than the cheapest'), findsOneWidget);
      final smallestNote = find.textContaining(
        'The smallest package is not always the cheapest',
      );
      await tester.scrollUntilVisible(smallestNote, 200);
      expect(smallestNote, findsOneWidget);
    });

    testWidgets('switching the common unit re-renders the exact prices', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOption(
        tester,
        label: 'Bag 750g',
        price: '90',
        quantity: '750',
        unitKey: 'g',
      );
      await addOption(tester, label: 'Bag 1kg', price: '115', quantity: '1');
      await tester.tap(find.byKey(const ValueKey('lens-common-g')));
      await tester.pumpAndSettle();
      expect(find.text('Cheapest per g'), findsOneWidget);
      expect(find.text('Bag 750g · 0.12 IRR per g'), findsOneWidget);
      expect(find.text('Bag 1kg · 0.115 IRR per g'), findsOneWidget);
    });

    testWidgets('a 2+1 free offer is honestly cheaper per piece', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOption(
        tester,
        label: 'Three for two',
        price: '300',
        quantity: '1',
        unitKey: 'piece',
        count: '3',
        paidCount: '2',
      );
      await addOption(
        tester,
        label: 'Single',
        price: '110',
        quantity: '1',
        unitKey: 'piece',
      );
      expect(find.text('Cheapest per piece'), findsOneWidget);
      expect(find.text('Three for two · 100 IRR per piece'), findsOneWidget);
      expect(find.text('Single · 110 IRR per piece'), findsOneWidget);
      expect(find.textContaining('paid 2, received 3'), findsOneWidget);
    });

    testWidgets('offers in different currencies are refused, not converted', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOption(tester, label: 'Local rice', price: '100', quantity: '1');
      // A second offer in dollars.
      await tester.tap(find.byKey(const ValueKey('lens-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lens-label')),
        'Imported rice',
      );
      await tester.tap(find.byKey(const ValueKey('lens-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      await tester.enterText(priceField(), '2');
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('lens-quantity')), '1');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Offers in different currencies cannot be compared',
        ),
        findsOneWidget,
      );
      expect(find.text('Cheapest'), findsNothing);
    });

    testWidgets('tomans enter as labelled, and land as rials', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('lens-add')));
      await tester.pumpAndSettle();
      expect(find.text('1 toman = 10 rials'), findsOneWidget);
      await tester.tap(find.text('Tomans'));
      await tester.pumpAndSettle();
      // The price field says Tomans beside the amount, like the shipping
      // and fixed-discount fields do — the typed number is tomans.
      expect(
        tester.widget<TextField>(priceField()).decoration!.suffixText,
        'Tomans',
      );
      await tester.enterText(find.byKey(const ValueKey('lens-label')), 'Rice');
      await tester.pump();
      await tester.enterText(priceField(), '25');
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('lens-quantity')), '1');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      // 25 tomans = 250 rials.
      expect(find.text('Total payable: 250 IRR'), findsOneWidget);
    });

    testWidgets('reset clears the offers and keeps the saved history', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOption(
        tester,
        label: 'Bag 750g',
        price: '90',
        quantity: '750',
        unitKey: 'g',
      );
      await addOption(tester, label: 'Bag 1kg', price: '115', quantity: '1');
      await openMenu(tester);
      await tester.tap(find.text('Save comparison'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      // Let the Saved snackbar expire so the next one is not queued.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip('Clear the offers — saved history stays'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cleared'), findsOneWidget);
      expect(find.text('Add an offer to start comparing'), findsOneWidget);
      expect(find.text('Bag 1kg'), findsNothing);

      await openMenu(tester);
      await tester.tap(find.text('Saved comparisons'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 offers'), findsOneWidget);
    });

    testWidgets('editing an offer updates the comparison', (tester) async {
      await pumpScreen(tester);
      await addOption(
        tester,
        label: 'Bag 750g',
        price: '90',
        quantity: '750',
        unitKey: 'g',
      );
      await addOption(tester, label: 'Bag 1kg', price: '115', quantity: '1');
      expect(find.text('Bag 750g · 120 IRR per kg'), findsOneWidget);

      await tester.tap(find.text('Bag 750g'));
      await tester.pumpAndSettle();
      expect(find.text('Edit offer'), findsOneWidget);
      await tester.enterText(priceField(), '60');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      expect(find.text('Bag 750g · 80 IRR per kg'), findsOneWidget);
      expect(find.text('Bag 1kg · 115 IRR per kg'), findsOneWidget);
      // The edited offer is now the cheapest.
      expect(
        find.textContaining('35 IRR more than the cheapest'),
        findsOneWidget,
      );
    });

    testWidgets('removing an offer asks first and keeps the others', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOption(
        tester,
        label: 'Bag 750g',
        price: '90',
        quantity: '750',
        unitKey: 'g',
      );
      await addOption(tester, label: 'Bag 1kg', price: '115', quantity: '1');
      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove this offer?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Bag 750g'), findsNothing);
      expect(find.text('Bag 1kg'), findsOneWidget);
      // One offer is not an empty state, and no comparison runs: the
      // honest screen shows the card and the add button, nothing more.
      expect(find.text('Cheapest'), findsNothing);
      expect(find.byKey(const ValueKey('lens-add')), findsOneWidget);
    });

    testWidgets(
      'the editor refuses bad input with named errors, and guards discards',
      (tester) async {
        await pumpScreen(tester);
        await tester.tap(find.byKey(const ValueKey('lens-add')));
        await tester.pumpAndSettle();
        // Nothing typed: save is refused, the label says so.
        await tester.tap(find.byKey(const ValueKey('lens-save')));
        await tester.pumpAndSettle();
        expect(find.text('Name the offer'), findsOneWidget);
        expect(find.text('New offer'), findsOneWidget); // still open

        // Negative prices are refused; explicit free offers are supported.
        await tester.enterText(priceField(), '-1');
        await tester.pump();
        expect(find.text('Numbers only — no signs or letters'), findsOneWidget);
        // A non-numeric quantity is named too (errors are live now).
        await tester.enterText(
          find.byKey(const ValueKey('lens-quantity')),
          'abc',
        );
        await tester.pump();
        expect(
          find.text('Numbers only — no signs or letters'),
          findsAtLeast(1),
        );

        // Leaving with unsaved work asks; discard closes it.
        // The sheet has no × — it closes the way back does.
        await tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .maybePop();
        await tester.pumpAndSettle();
        expect(find.text('Discard this offer?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.text('Add an offer to start comparing'), findsOneWidget);
      },
    );
  });
}
