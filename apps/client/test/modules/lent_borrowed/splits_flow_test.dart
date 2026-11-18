import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// Splitting a cost end to end: two people, one dinner, a settle-up that
/// becomes an ordinary loan in one tap, and a delete that can be undone.
void main() {
  Future<NexTestHarness> harness() async {
    final h = await NexTestHarness.create(name: 'lent_splits_');
    addTearDown(h.dispose);
    return h;
  }

  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Future<void> openSplits(WidgetTester tester, NexModuleStore store) async {
    await tester.pumpWidget(app(LoansScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('loans-units')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Splits'));
    await tester.pumpAndSettle();
  }

  Future<void> addSplitCost(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('split-add-cost')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('split-cost-amount')),
      '30000',
    );
    await tester.tap(find.byKey(const ValueKey('split-cost-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('a dinner split shows who pays whom, and records the loan', (
    tester,
  ) async {
    final h = await harness();
    final store = NexModuleStore(h.services, 'lent_borrowed');
    await openSplits(tester, store);

    expect(find.text('Splits'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('splits-empty-add')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('split-field-title')),
      'Trip',
    );
    for (final person in ['Ali', 'Sara']) {
      await tester.enterText(
        find.byKey(const ValueKey('split-field-person')),
        person,
      );
      await tester.tap(find.byKey(const ValueKey('split-add-person')));
      await tester.pumpAndSettle();
    }
    await addSplitCost(tester);
    await tester.tap(find.byKey(const ValueKey('split-save')));
    await tester.pumpAndSettle();

    final split = (await store.list('split')).single;
    expect(split.body['title'], 'Trip');
    expect(split.body['me'], 'Ali');
    expect(find.text('Trip'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('split-${split.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sara pays Ali'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('split-record-0')));
    await tester.pumpAndSettle();

    final loan = (await store.list('loan')).single;
    expect(loan.body['person'], 'Sara');
    expect(loan.body['direction'], 'lent');
    expect(loan.body['amount'], 150000);
    expect(loan.body['note'], contains('Trip'));
    expect(loan.body['issued'], Loan.fromBody('x', loan.body).issued);
    expect(find.text('Recorded in Lent'), findsOneWidget);

    // A second tap must not create a second loan for the same transfer.
    await tester.tap(find.byKey(const ValueKey('split-record-0')));
    await tester.pumpAndSettle();
    expect(await store.list('loan'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a split is deleted with Undo, costs and all', (tester) async {
    final h = await harness();
    final store = NexModuleStore(h.services, 'lent_borrowed');
    await store.put('split', 's1', {
      'v': 1,
      'title': 'Flat',
      'date': '2026-11-01',
      'me': 'Ali',
      'people': ['Ali', 'Sara'],
      'costs': [
        {
          'id': 'c1',
          'title': 'Internet',
          'amount': 400000,
          'payer': 'Sara',
          'mode': 'equal',
          'parts': {'Ali': 0, 'Sara': 0},
        },
      ],
    });
    await openSplits(tester, store);
    await tester.tap(find.byKey(const ValueKey('split-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('split-delete')));
    await tester.pumpAndSettle();
    expect(await store.list('split'), isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await store.list('split'), hasLength(1));
    expect(
      ((await store.list('split')).single.body['costs'] as List),
      hasLength(1),
    );
  });

  testWidgets('Persian splits say the amounts in Persian, toman by default', (
    tester,
  ) async {
    final h = await harness();
    final store = NexModuleStore(h.services, 'lent_borrowed');
    await store.put('split', 's1', {
      'v': 1,
      'title': 'سفر',
      'date': '2026-11-01',
      'me': 'علی',
      'people': ['علی', 'سارا'],
      'costs': [
        {
          'id': 'c1',
          'title': 'شام',
          'amount': 300000,
          'payer': 'علی',
          'mode': 'equal',
          'parts': {'علی': 0, 'سارا': 0},
        },
      ],
    });
    await tester.pumpWidget(
      app(LoansScreen(store: store), locale: const Locale('fa')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('loans-units')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دنگ‌ها'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('split-s1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('۱۵٬۰۰۰ تومان'), findsWidgets);
    expect(find.textContaining('به علی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
