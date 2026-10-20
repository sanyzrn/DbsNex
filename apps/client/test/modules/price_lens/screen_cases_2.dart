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

      // Back into the calculator — the typed offers are replaced, and
      // replacing them is confirmed first because they are the person's.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Replace the current offers?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 offers'), findsOneWidget); // still open
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace'));
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

  group('the shared shopping-date entry', () {
    Future<void> startOffer(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('lens-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('lens-label')), 'Rice');
      await tester.pump();
      await tester.enterText(priceField(), '100');
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('lens-quantity')), '1');
      await tester.pump();
    }

    testWidgets('a typed shopping date rides along into the price memory', (
      tester,
    ) async {
      await pumpScreen(tester);
      await startOffer(tester);
      await tester.enterText(
        find.byKey(const ValueKey('lens-date')),
        '2026/03/14',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      // The offer is dated, so remembering it needs no extra picker.
      await tester.tap(find.byTooltip('Remember this price'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      await openMenu(tester);
      await tester.tap(find.text('Price memory'));
      await tester.pumpAndSettle();
      expect(find.text('Rice · 100 IRR on 2026/03/14'), findsOneWidget);
    });

    testWidgets('the shared calendar button fills the date field', (
      tester,
    ) async {
      await pumpScreen(tester);
      await startOffer(tester);
      final calendar = find.byIcon(Icons.calendar_month_outlined);
      await tester.ensureVisible(calendar);
      await tester.pumpAndSettle();
      await tester.tap(calendar);
      await tester.pumpAndSettle();
      // The shared picker's input mode, in the locale's own format.
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '3/14/2026');
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('lens-date')))
            .controller!
            .text,
        '2026/03/14',
      );
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
    });

    testWidgets('a future or impossible shopping date is refused live', (
      tester,
    ) async {
      await pumpScreen(tester);
      await startOffer(tester);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.enterText(
        find.byKey(const ValueKey('lens-date')),
        '${tomorrow.year}'
        '/${tomorrow.month.toString().padLeft(2, '0')}'
        '/${tomorrow.day.toString().padLeft(2, '0')}',
      );
      await tester.pump();
      expect(
        find.text(
          'Choose a valid shopping date, not in the future — or clear it',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      expect(find.text('New offer'), findsOneWidget); // refused, still open

      await tester.enterText(
        find.byKey(const ValueKey('lens-date')),
        '2026/2/30',
      );
      await tester.pump();
      expect(
        find.text(
          'Choose a valid shopping date, not in the future — or clear it',
        ),
        findsOneWidget,
      );

      // Clearing is the honest exit for an offer without a date.
      await tester.ensureVisible(find.text('Clear date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear date'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
    });
  });

  group('ties and Persian digits on the cards', () {
    testWidgets('three equal offers say how many tie', (tester) async {
      await pumpScreen(tester);
      for (final label in ['A', 'B', 'C']) {
        await addOption(tester, label: label);
      }
      await tester.scrollUntilVisible(
        find.text('3 offers tie at the lowest price'),
        200,
      );
      expect(find.text('3 offers tie at the lowest price'), findsOneWidget);
    });

    testWidgets('Persian quantities and discounts render in Persian digits', (
      tester,
    ) async {
      await pumpScreen(tester, locale: const Locale('fa'));
      await tester.tap(find.byKey(const ValueKey('lens-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('lens-label')), 'برنج');
      await tester.pump();
      await tester.enterText(priceField(), '90');
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('lens-quantity')),
        '750',
      );
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('lens-count')), '3');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('lens-unit-g')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lens-unit-g')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('lens-discount-percent')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lens-discount-percent')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lens-discount-value')),
        '10',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('۷۵۰ گرم × ۳'), findsOneWidget);
      expect(find.textContaining('۱۰%'), findsOneWidget);
    });
  });

  group('languages, themes, scales and screens', () {
    testWidgets('Persian, right to left, in the dark', (tester) async {
      await pumpScreen(tester, locale: const Locale('fa'), dark: true);
      expect(
        find.text('برای شروع مقایسه، یک پیشنهاد اضافه کنید'),
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
