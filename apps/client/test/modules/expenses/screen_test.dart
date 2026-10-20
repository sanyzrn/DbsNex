import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/controller.dart';
import 'package:nex_client/modules/expenses/expenses_form.dart';
import 'package:nex_client/modules/expenses/expenses_screen.dart';
import 'package:nex_client/modules/expenses/local_values.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// The Expenses screen, end to end over a real store: empty state,
/// adding expenses and income in rial, toman and dollars, editing,
/// deleting with Undo, month navigation and all-time, filters, search,
/// budgets, templates, persistence — and Persian RTL, dark, small
/// screens and 2.0 text scale.
part 'screen_cases_1.dart';
part 'screen_cases_2.dart';
part 'screen_cases_3.dart';

late NexTestHarness harness;
late NexModuleStore store;

Future<void> pumpScreen(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
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
      theme: theme ?? (dark ? nexDarkTheme() : nexLightTheme()),
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

Future<void> addPayment(
  WidgetTester tester, {
  String amount = '1250',
  bool income = false,
  String? note,
}) async {
  await tester.tap(find.byKey(const ValueKey('expenses-add')));
  await tester.pumpAndSettle();
  if (income) {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('expenses-type')),
        matching: find.text('Income'),
      ),
    );
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byKey(const ValueKey('expenses-amount')), amount);
  if (note != null) {
    await tester.enterText(find.byKey(const ValueKey('expenses-note')), note);
  }
  await tester.tap(find.byKey(const ValueKey('expenses-save')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_exw_');
    store = NexModuleStore(harness.services, 'expenses');
  });
  tearDown(() async => harness.dispose());

  _screenCases1();
  _screenCases2();
  _screenCases3();
}
