import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/expenses_screen.dart';
import 'package:nex_client/modules/expenses/expenses_share.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/expenses/money.dart';
import 'package:nex_client/modules/expenses/strings.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

/// The Expenses screen end to end over a real store: a payment in seconds,
/// Persian digits, the month the person reads, income and what is left,
/// correcting and deleting with Undo, filters by words and amount,
/// budgets, the recurring offer, hiding amounts, templates, sharing and
/// the states a failed read leaves.
part 'screen_flows.dart';
part 'screen_states.dart';

late NexTestHarness harness;
late NexModuleStore store;

Future<void> pumpScreen(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  Size size = const Size(800, 1600),
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: dark ? nexDarkTheme() : nexLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          platformBrightness: dark ? Brightness.dark : Brightness.light,
        ),
        child: ExpensesScreen(store: store),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Adds a payment the short way: amount, a category, Save. Today is already
/// the answer to "when".
Future<void> addPayment(
  WidgetTester tester, {
  String amount = '1250',
  String? category,
  bool income = false,
  String? note,
  String? day,
}) async {
  await tester.tap(find.byKey(const ValueKey('expenses-add')));
  await tester.pumpAndSettle();
  if (income) {
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byKey(const ValueKey('expenses-amount')), amount);
  await tester.pumpAndSettle();
  if (category != null) {
    await tester.tap(find.byKey(const ValueKey('expenses-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(category));
    await tester.pumpAndSettle();
  }
  if (note != null) {
    await tester.tap(find.byKey(const ValueKey('expenses-more')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('expenses-note')), note);
    await tester.pumpAndSettle();
  }
  if (day != null) {
    await tester.tap(find.byKey(const ValueKey('expenses-more')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('expenses-date')), day);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('expenses-save')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_exscreen_');
    store = NexModuleStore(harness.services, 'expenses');
  });
  tearDown(() async => harness.dispose());

  _flows();
  _states();
}
