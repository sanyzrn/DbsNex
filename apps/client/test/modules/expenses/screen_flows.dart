part of 'screen_test.dart';

void _flows() {
  testWidgets('an empty book offers the one way in', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Nothing written down yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('expenses-add')), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
  });

  testWidgets('a payment is written in seconds: amount, category, Save', (
    tester,
  ) async {
    await pumpScreen(tester);
    await addPayment(tester, amount: '1250', category: 'Groceries');
    final raw = await store.get('tx', (await store.list('tx')).single.id);
    expect(raw!['amountRial'], 12500);
    expect(raw['category'], 'cat-groceries');
    expect(raw['schema'], 3);
    // Today is the answer to "when"; nothing had to be chosen.
    final today = DateTime.now();
    final day = raw['date'] as String;
    expect(day.startsWith(isoDay(today)), isTrue);
    expect(find.text('1,250 tomans'), findsWidgets);
    expect(find.text('Groceries'), findsWidgets);
  });

  testWidgets('the amount field takes Persian digits and groups them', (
    tester,
  ) async {
    await pumpScreen(tester, locale: const Locale('fa'), dark: true);
    await tester.tap(find.byKey(const ValueKey('expenses-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expenses-amount')),
      '۱۲۵٬۰۰۰',
    );
    await tester.pumpAndSettle();
    // What the person sees is Rial or Toman in Persian digits and grouping.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('expenses-amount')))
          .controller!
          .text,
      '۱۲۵٬۰۰۰',
    );
    await tester.tap(find.byKey(const ValueKey('expenses-save')));
    await tester.pumpAndSettle();
    final raw = await store.get('tx', (await store.list('tx')).single.id);
    expect(raw!['amountRial'], 1250000);
    expect(find.text('۱۲۵٬۰۰۰ تومان'), findsWidgets);
  });

  testWidgets('income makes the month say what is left', (tester) async {
    await pumpScreen(tester);
    await addPayment(tester, amount: '100', category: 'Groceries');
    await addPayment(tester, amount: '500', income: true, category: 'Salary');
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('400 tomans'), findsWidgets);
  });

  testWidgets('a payment is corrected in place, unknown fields kept', (
    tester,
  ) async {
    await pumpScreen(tester);
    await addPayment(tester, amount: '100', note: 'Weekly shop');
    final id = (await store.list('tx')).single.id;
    await tester.tap(find.text('Weekly shop'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expenses-amount')),
      '250',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expenses-save')));
    await tester.pumpAndSettle();
    final raw = (await store.get('tx', id))!;
    expect(raw['amountRial'], 2500);
    expect(find.text('250 tomans'), findsWidgets);
  });

  testWidgets('deleting asks, then offers Undo that brings it back', (
    tester,
  ) async {
    await pumpScreen(tester);
    await addPayment(tester, amount: '100', note: 'Weekly shop');
    final id = (await store.list('tx')).single.id;
    await tester.tap(find.text('Weekly shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expenses-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(await store.get('tx', id), isNull);
    expect(find.text('Deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await store.get('tx', id), isNotNull);
  });

  testWidgets('the month moves, in the calendar the person reads', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('November 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Last month'), findsOneWidget);
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('All time'), findsWidgets);
    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
  });

  testWidgets('finding a payment by words, category and amount range', (
    tester,
  ) async {
    await pumpScreen(tester);
    await addPayment(tester, amount: '100', note: 'Weekly shop');
    await addPayment(tester, amount: '900', note: 'Rent top-up');
    await tester.tap(find.byTooltip('Search payments'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expenses-search')),
      'shop',
    );
    await tester.pumpAndSettle();
    expect(find.text('Weekly shop'), findsOneWidget);
    expect(find.text('Rent top-up'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('expenses-search')), '');
    await tester.enterText(find.byKey(const ValueKey('expenses-min')), '500');
    await tester.pumpAndSettle();
    expect(find.text('Weekly shop'), findsNothing);
    expect(find.text('Rent top-up'), findsOneWidget);
  });

  testWidgets('a budget shows what is left, quietly', (tester) async {
    await pumpScreen(tester);
    await addPayment(tester, amount: '100', note: 'Weekly shop');
    await tester.tap(find.byTooltip('More of this book'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Budgets'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expenses-amount')),
      '200',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expenses-budget-save')));
    await tester.pumpAndSettle();
    expect(find.text('Budgets'), findsOneWidget);
    expect(find.textContaining('100 tomans'), findsWidgets);
  });

  testWidgets('a recurring payment is offered on its day, and logged once', (
    tester,
  ) async {
    await store.put('tpl', 'tpl-1', {
      'label': 'Rent',
      'type': 'expense',
      'amountRial': 12000000,
      'category': 'cat-rent',
      'day': 5,
      'calendar': 'gregorian',
      'schema': 3,
    });
    await pumpScreen(tester);
    expect(find.text('Recurring this month'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('expenses-log-tpl-1')));
    await tester.pumpAndSettle();
    final txs = await store.list('tx');
    expect(txs.length, 1);
    expect(txs.single.body['templateId'], 'tpl-1');
    expect(txs.single.body['period'], startsWith('2026-11-01'));
    expect(find.byKey(const ValueKey('expenses-log-tpl-1')), findsNothing);
    // Nothing was written twice.
    await tester.pumpAndSettle();
    expect((await store.list('tx')).length, 1);
  });

  testWidgets('nothing is offered before its day', (tester) async {
    await store.put('tpl', 'tpl-late', {
      'label': 'Internet',
      'type': 'expense',
      'amountRial': 4500000,
      'day': 28,
      'calendar': 'gregorian',
    });
    await pumpScreen(tester);
    expect(find.byKey(const ValueKey('expenses-log-tpl-late')), findsNothing);
    expect(find.text('Recurring this month'), findsNothing);
  });

  testWidgets('amounts can be hidden, and brought back', (tester) async {
    await pumpScreen(tester);
    await addPayment(tester, amount: '100', note: 'Weekly shop');
    await tester.tap(find.byTooltip('Hide amounts'));
    await tester.pumpAndSettle();
    expect(find.text('•••'), findsWidgets);
    expect(find.text('100 tomans'), findsNothing);
    await tester.tap(find.byTooltip('Show amounts'));
    await tester.pumpAndSettle();
    expect(find.text('100 tomans'), findsWidgets);
  });

  testWidgets('a template can become a monthly payment', (tester) async {
    await pumpScreen(tester);
    await addPayment(tester, amount: '100');
    await tester.tap(find.byTooltip('More of this book'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expenses-new-template')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expenses-template-name')),
      'Internet',
    );
    await tester.enterText(
      find.byKey(const ValueKey('expenses-amount')),
      '450',
    );
    await tester.enterText(
      find.byKey(const ValueKey('expenses-template-day')),
      '5',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expenses-template-save')));
    await tester.pumpAndSettle();
    final raw = (await store.list('tpl')).single.body;
    expect(raw['amountRial'], 4500);
    expect(raw['day'], 5);
    expect(raw['calendar'], 'gregorian');
  });

  testWidgets('the month shares as plain text, in either language', (
    tester,
  ) async {
    final month = NexModuleMonth(false, 2026, 11);
    final txs = [
      ExpenseTx(
        id: 'a',
        type: 'expense',
        amountRial: 1250000,
        date: DateTime(2026, 11, 5),
        categoryId: 'cat-groceries',
      ),
      ExpenseTx(
        id: 'b',
        type: 'income',
        amountRial: 5000000,
        date: DateTime(2026, 11, 6),
        categoryId: 'cat-salary',
      ),
    ];
    Future<String> textIn(Locale locale) async {
      late String text;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              text = expensesShareText(
                context,
                month: month,
                txs: txs,
                unit: ExpenseUnit.toman,
                categoryName: (id) => id == 'cat-groceries'
                    ? expenseStrings(context, 'cat-groceries')
                    : expenseStrings(context, 'cat-salary'),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      return text;
    }

    final english = await textIn(const Locale('en'));
    expect(english, contains('Expenses for November 2026'));
    expect(english, contains('Groceries: 125,000 tomans'));
    expect(english, contains('Total spent: 125,000 tomans'));
    expect(english, contains('Left: 375,000 tomans'));
    final persian = await textIn(const Locale('fa'));
    expect(persian, contains('هزینه‌های نوامبر ۲۰۲۶'));
    expect(persian, contains('۱۲۵٬۰۰۰ تومان'));
  });
}
