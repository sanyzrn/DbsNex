part of 'screen_test.dart';

void _screenCases2() {
  group('budgets and templates', () {
    testWidgets('a budget shows spent, left and its arithmetic', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '3000');
      await tester.tap(find.byTooltip('Expenses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Budgets'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-budget-overall')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '5000',
      );
      await tester.tap(find.byKey(const ValueKey('expenses-budget-save')));
      await tester.pumpAndSettle();
      expect(find.text('Monthly limit — all categories'), findsOneWidget);
      expect(find.text('3,000 / 5,000 IRR'), findsOneWidget);
      expect(find.text('Left 2,000 IRR'), findsOneWidget);
    });

    testWidgets('a template fills the form on confirmation', (tester) async {
      final controller = ExpensesController(store);
      await controller.load();
      await controller.saveTemplate(
        const ExpenseTemplate(
          id: 'tpl-rent',
          label: 'Rent',
          type: 'expense',
          amount: 25000000,
          currency: 'IRR',
          categoryId: 'cat-home',
        ),
      );
      controller.dispose();

      await pumpScreen(tester);
      await tester.tap(find.byTooltip('Expenses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      expect(find.text('Rent'), findsOneWidget);
      expect(
        find.text(
          'A template fills the entry form when you confirm it — nothing is '
          'ever charged in the background',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Rent'));
      await tester.pumpAndSettle();
      expect(find.text('New expense'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('expenses-amount')),
      );
      expect(field.controller!.text, '250000');
    });
  });

  group('persistence and the platform contract', () {
    testWidgets('records survive reopening the screen', (tester) async {
      await pumpScreen(tester);
      await addPayment(tester, amount: '1500', note: 'persists');
      // A brand-new screen over the same store, as after reopening.
      await pumpScreen(tester);
      expect(find.text('persists'), findsOneWidget);
      expect(find.text('1,500 IRR'), findsAtLeast(1));
    });
  });

  group('languages, themes and sizes', () {
    testWidgets('Persian reads right to left with Persian words', (
      tester,
    ) async {
      await pumpScreen(tester, locale: const Locale('fa'));
      expect(find.text('هزینه‌ها'), findsOneWidget);
      expect(find.text('هنوز چیزی ثبت نشده'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('هزینه‌ها'))),
        TextDirection.rtl,
      );
      await addPayment(tester, amount: '1250');
      expect(find.text('۱٬۲۵۰ IRR'), findsAtLeast(1));
      // No category picked: it reads as متفرقه, with Persian digits.
      expect(find.text('متفرقه'), findsAtLeast(1));
      expect(find.text('۱۰۰٪'), findsOneWidget);
      expect(find.text('این ماه'), findsOneWidget);
    });

    testWidgets('dark theme keeps every label legible', (tester) async {
      await pumpScreen(tester, dark: true);
      await addPayment(tester, amount: '900');
      expect(find.text('900 IRR'), findsAtLeast(1));
      expect(find.text('This month'), findsOneWidget);
    });

    testWidgets('a small screen scrolls instead of overflowing', (
      tester,
    ) async {
      await pumpScreen(tester, size: const Size(360, 640));
      await addPayment(tester, amount: '100');
      expect(tester.takeException(), isNull);
      expect(find.text('100 IRR'), findsAtLeast(1));
    });

    testWidgets('text at 2.0 scale still lays out', (tester) async {
      await pumpScreen(tester, textScale: 2.0, size: const Size(400, 1800));
      await addPayment(tester, amount: '100');
      expect(tester.takeException(), isNull);
      expect(find.text('This month'), findsOneWidget);
    });
  });
}
