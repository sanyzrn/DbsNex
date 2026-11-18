import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loan_detail_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';
import 'loans_test_tools.dart';

/// A record exactly as the current version writes it: the upgrade adds
/// records beside it, never into it. Nothing may be lost, renamed or changed
/// in meaning, and an untouched save must write the same fields back.
void main() {
  Future<NexTestHarness> harness() async {
    final h = await NexTestHarness.create(name: 'lent_upgrade_');
    addTearDown(h.dispose);
    return h;
  }

  const loan = <String, Object?>{
    'v': 2,
    'currency': 'IRR',
    'currencyDecimals': 0,
    'direction': 'lent',
    'person': 'Sara',
    'type': 'money',
    'amount': 500000,
    'what': '',
    'issued': '2026-10-01',
    'due': '2026-10-15',
    'note': 'Train ticket',
    'reminderDetail': true,
  };
  const returned = <String, Object?>{
    'loan': 'l1',
    'date': '2026-10-05',
    'amount': 200000,
  };
  const settings = <String, Object?>{'v': 1, 'irrUnit': 'rial'};
  const draft = <String, Object?>{
    'v': 1,
    'base': 'l1',
    'fields': {'person': 'Sara typed'},
  };

  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  testWidgets('the list and the record read exactly as before', (tester) async {
    final h = await harness();
    final store = NexModuleStore(h.services, 'lent_borrowed');
    await store.put('loan', 'l1', loan);
    await store.put('return', 'r1', returned);
    await store.put('settings', 'settings', settings);
    await tester.pumpWidget(app(LoansScreen(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('Sara'), findsOneWidget);
    // The rial preference in the old settings record still decides how the
    // remaining 300,000 rials are said.
    expect(find.textContaining('300,000 rials'), findsWidgets);

    await tester.tap(find.text('Sara'));
    await tester.pumpAndSettle();
    expect(find.textContaining('500,000 rials'), findsWidgets);
    await revealInLoanDetail(tester, find.textContaining('200,000 rials'));
    expect(find.textContaining('200,000 rials'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an untouched save writes the same body back', (tester) async {
    final h = await harness();
    final store = NexModuleStore(h.services, 'lent_borrowed');
    await store.put('loan', 'l1', loan);
    await store.put('return', 'r1', returned);
    await store.put('settings', 'settings', settings);
    await store.put('draft', 'loan:l1', draft);
    await tester.pumpWidget(app(LoanDetailScreen(store: store, loanId: 'l1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('loan-edit')));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('loan-save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await settleLoans(tester);

    final written = (await store.get('loan', 'l1'))!;
    expect(written, loan);
    expect(await store.get('return', 'r1'), returned);
    expect(await store.get('settings', 'settings'), settings);
    // Saving is what clears a draft; it is not silently rewritten.
    expect(await store.get('draft', 'loan:l1'), isNull);
    expect(await store.list('split'), isEmpty);
    expect(await store.list('card'), isEmpty);
  });
}
