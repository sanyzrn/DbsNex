part of 'screen_test.dart';

void _screenCases2() {
  group('price memory', () {
    testWidgets('remembering, listing, deleting with Undo', (tester) async {
      await pumpScreen(tester);
      await addOption(tester, label: 'Rice', price: '100', quantity: '1');
      await tester.tap(find.byTooltip('Remember this price'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '10/01/2026');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      // Let the Saved snackbar expire so Forgotten is not queued behind it.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      await openMenu(tester);
      await tester.tap(find.text('Price memory'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rice · 100 IRR'), findsOneWidget);
      expect(
        find.text(
          'Only prices you entered yourself, with their date — never a market rate',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Forget this price?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Forgotten'), findsOneWidget);
      expect(find.text('Nothing remembered yet'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rice · 100 IRR'), findsOneWidget);
    });

    testWidgets('a matching offer shows the dated, mathematical difference', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOption(tester, label: 'Rice', price: '100', quantity: '1');
      await tester.tap(find.byTooltip('Remember this price'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '10/01/2026');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // The same spec, re-entered at a higher price, then a second
      // offer so the panel (which carries the memory line) appears.
      await tester.tap(find.text('Rice'));
      await tester.pumpAndSettle();
      await tester.enterText(priceField(), '120');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      await addOption(tester, label: 'Oil', price: '80', quantity: '1');
      expect(
        find.textContaining('Now 20 IRR more than you entered'),
        findsOneWidget,
      );
    });
  });

  group('saved comparisons', () {
    testWidgets('save, reopen into the calculator, delete with Undo', (
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

      await openMenu(tester);
      await tester.tap(find.text('Saved comparisons'));
      await tester.pumpAndSettle();
      expect(find.text('No saved comparisons yet'), findsNothing);
      expect(find.textContaining('2 offers'), findsOneWidget);

      // Back into the calculator.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Bag 750g'), findsOneWidget);
      expect(find.text('Cheapest per kg'), findsOneWidget);

      // Delete, then Undo from the SnackBar.
      await openMenu(tester);
      await tester.tap(find.text('Saved comparisons'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this comparison?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No saved comparisons yet'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 offers'), findsOneWidget);
    });
  });

  group('languages, themes, scales and screens', () {
    testWidgets('Persian, right to left, in the dark', (tester) async {
      await pumpScreen(tester, locale: const Locale('fa'), dark: true);
      expect(
        find.text('برای مقایسه، پیشنهاد دوم را اضافه کنید'),
        findsOneWidget,
      );
      expect(
        Directionality.of(tester.element(find.text('ذره‌بین قیمت'))),
        TextDirection.rtl,
      );

      await addOption(
        tester,
        label: 'برنج',
        price: '90',
        quantity: '750',
        unitKey: 'g',
      );
      await addOption(tester, label: 'برنج درشت', price: '115', quantity: '1');
      expect(find.text('ارزان‌ترین به ازای کیلوگرم'), findsOneWidget);
      expect(find.text('برنج · ۱۲۰ IRR به ازای کیلوگرم'), findsOneWidget);
      expect(find.text('برنج درشت · ۱۱۵ IRR به ازای کیلوگرم'), findsOneWidget);
      expect(find.text('۵ IRR بیشتر از ارزان‌ترین'), findsOneWidget);
      expect(find.text('ارزان‌ترین'), findsOneWidget);
    });

    testWidgets('text scale 2.0 keeps the flow working', (tester) async {
      await pumpScreen(tester, textScale: 2.0);
      await addOption(
        tester,
        label: 'Bag 750g',
        price: '90',
        quantity: '750',
        unitKey: 'g',
      );
      await addOption(tester, label: 'Bag 1kg', price: '115', quantity: '1');
      expect(find.text('Cheapest per kg'), findsOneWidget);
      expect(find.text('Bag 1kg · 115 IRR per kg'), findsOneWidget);
    });

    testWidgets('a small screen keeps the flow working', (tester) async {
      await pumpScreen(tester, size: const Size(360, 640));
      await addOption(
        tester,
        label: 'Bag 750g',
        price: '90',
        quantity: '750',
        unitKey: 'g',
      );
      await addOption(tester, label: 'Bag 1kg', price: '115', quantity: '1');
      await tester.scrollUntilVisible(find.text('Cheapest per kg'), 200);
      expect(find.text('Cheapest per kg'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('5 IRR more than the cheapest'),
        200,
      );
      expect(find.text('5 IRR more than the cheapest'), findsOneWidget);
    });
  });
}
