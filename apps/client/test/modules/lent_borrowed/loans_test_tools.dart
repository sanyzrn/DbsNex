import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';

import '../../support/nex_harness.dart';

/// The pieces every lent_borrowed flow test needs: a screen over a real
/// store, a settle that waits out the draft debounce, and a record created
/// through the real editor sheet.

Widget pumpableLoansScreen(
  NexModuleStore store, {
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: LoansScreen(store: store),
);

Future<NexModuleStore> pumpLoansScreen(
  WidgetTester tester, {
  required NexTestHarness harness,
  Locale locale = const Locale('en'),
}) async {
  final store = NexModuleStore(harness.services, 'lent_borrowed');
  await tester.pumpWidget(pumpableLoansScreen(store, locale: locale));
  await tester.pumpAndSettle();
  return store;
}

Future<void> settleLoans(WidgetTester tester) async {
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
    await tester.enterText(find.byKey(const ValueKey('loan-field-what')), what);
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
  await settleLoans(tester);
  final loans = await store.list('loan');
  expect(
    loans.length,
    before.length + 1,
    reason: 'the record was really saved',
  );
  return loans.first.id;
}
