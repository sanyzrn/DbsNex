import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/price_lens/price_lens_screen.dart';

import '../../support/nex_harness.dart';

/// The Price Lens screen, end to end over a real store: the live
/// calculator's whole journey — empty state, adding offers in several
/// currencies and units, the exact result, reset that keeps history,
/// price memory and saved comparisons with Undo — plus Persian RTL,
/// dark, small screens and 2.0 text scale.
part 'screen_cases_1.dart';
part 'screen_cases_2.dart';
part 'screen_cases_3.dart';

late NexTestHarness harness;
late NexModuleStore store;

Future<void> pumpScreen(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  bool dark = false,
  double textScale = 1.0,
  Size size = const Size(800, 1600),
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
        child: PriceLensScreen(store: store),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder priceField() => find.descendant(
  of: find.byKey(const ValueKey('lens-price')),
  matching: find.byType(TextField),
);

Future<void> addOption(
  WidgetTester tester, {
  String label = 'Rice',
  String price = '100',
  String quantity = '1',
  String unitKey = 'kg',
  String count = '1',
  String? paidCount,
}) async {
  await tester.tap(find.byKey(const ValueKey('lens-add')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('lens-label')), label);
  await tester.pump();
  await tester.enterText(priceField(), price);
  await tester.pump();
  await tester.enterText(find.byKey(const ValueKey('lens-quantity')), quantity);
  await tester.pump();
  await tester.enterText(find.byKey(const ValueKey('lens-count')), count);
  await tester.pump();
  if (paidCount != null) {
    await tester.enterText(
      find.byKey(const ValueKey('lens-paid-count')),
      paidCount,
    );
    await tester.pump();
  }
  if (unitKey != 'kg') {
    await tester.ensureVisible(find.byKey(ValueKey('lens-unit-$unitKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('lens-unit-$unitKey')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('lens-save')));
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More actions'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_plw_');
    store = NexModuleStore(harness.services, 'price_lens');
  });
  tearDown(() async => harness.dispose());

  _screenCases1();
  _screenCases2();
  _screenCases3();
}
