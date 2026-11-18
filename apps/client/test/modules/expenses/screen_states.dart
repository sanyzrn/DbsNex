part of 'screen_test.dart';

void _states() {
  testWidgets('a read that fails says so and offers Retry', (tester) async {
    final fault = _FaultStore(harness.services);
    store = fault;
    await pumpScreen(tester);
    expect(
      find.text('Could not read your saved data. Retry before changing it.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('an incomplete record is shown, named, and repairable', (
    tester,
  ) async {
    await store.put('tx', 'tx-foreign', {
      'type': 'expense',
      'amount': 1250,
      'currency': 'USD',
      'date': '2026-11-05T12:00:00',
    });
    await pumpScreen(tester);
    expect(find.text('Incomplete record'), findsWidgets);
    // The notice goes to all time, where the record can be opened and fixed.
    await tester.tap(find.byKey(const ValueKey('expenses-incomplete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expenses-tx-tx-foreign')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expenses-amount')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Persian dark at 320×480 and scale 2 holds its layout', (
    tester,
  ) async {
    await store.put('tx', 't1', {
      'type': 'expense',
      'amountRial': 2850000,
      'date': DateTime.now().toIso8601String(),
      'category': 'cat-groceries',
      'note': 'خرید هفتگی',
    });
    await pumpScreen(
      tester,
      locale: const Locale('fa'),
      dark: true,
      textScale: 2,
      size: const Size(320, 480),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('expenses-add')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('expenses-amount')), findsOneWidget);
    // The optional half opens, too, without an overflow.
    await tester.ensureVisible(find.byKey(const ValueKey('expenses-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expenses-more')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('English light at a normal phone size, all sections', (
    tester,
  ) async {
    final now = DateTime.now();
    await store.put('tx', 't1', {
      'type': 'expense',
      'amountRial': 28500000,
      'date': now.toIso8601String(),
      'category': 'cat-groceries',
      'note': 'Groceries',
    });
    await store.put('tx', 't2', {
      'type': 'income',
      'amountRial': 120000000,
      'date': now.toIso8601String(),
      'category': 'cat-salary',
    });
    final month = NexModuleMonth.of(now, solar: false);
    await store.put('budget', 'budget-${monthStartIso(month)}-all', {
      'start': monthStartIso(month),
      'amountRial': 40000000,
    });
    await pumpScreen(tester, size: const Size(390, 844));
    expect(find.text('Groceries'), findsWidgets);
    expect(find.text('Budgets'), findsOneWidget);
    expect(find.text('Spending by category'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FaultStore extends NexModuleStore {
  _FaultStore(NexServices services) : super(services, 'expenses');

  @override
  Future<List<ModuleRecord>> list(String kind) {
    if (kind == 'tx') return Future.error(StateError('read'));
    return super.list(kind);
  }
}
