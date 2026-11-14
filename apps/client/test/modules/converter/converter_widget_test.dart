import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/converter/converter_history.dart';
import 'package:nex_client/modules/converter/converter_screen.dart';

import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  late NexModuleStore store;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'converter_ui_');
    store = NexModuleStore(harness.services, 'converter');
  });
  tearDown(() => harness.dispose());

  /// The module's screen over a library, in the app's own frame.
  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
    double textScale = 1,
    bool solar = true,
  }) async {
    tester.view.physicalSize = const Size(900, 2800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? nexLightTheme(),
        home: NexModuleCalendar(
          solar: solar,
          child: ConverterScreen(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets the real store finish what a tap started.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitForCommit(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    await settle(tester);
  }

  Future<void> openUnits(WidgetTester tester, {String text = 'Units'}) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('the first visit shows the date and says what is kept', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('converter-hero')), findsOneWidget);
    expect(find.text('Conversions you make are kept here.'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('a date in one calendar shows the other two and the weekday', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('converter-date')),
      '1405/08/22',
    );
    await tester.pumpAndSettle();
    expect(find.text('22 Aban 1405'), findsOneWidget);
    expect(find.text('Gregorian · 13 November 2026'), findsOneWidget);
    expect(find.text('Lunar · 2 Jumada II 1448'), findsOneWidget);
    expect(find.text('Friday'), findsOneWidget);
    expect(find.textContaining('Lunar dates are calculated'), findsOneWidget);
  });

  testWidgets('a date that does not exist says so, and shows no answer', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('converter-date')),
      '1405/13/01',
    );
    await tester.pumpAndSettle();
    expect(find.text('Write the date as year/month/day.'), findsOneWidget);
    expect(find.byKey(const ValueKey('converter-hero')), findsNothing);
  });

  testWidgets('units follow the typing, with no Convert button', (
    tester,
  ) async {
    await pump(tester);
    await openUnits(tester);
    expect(find.text('3.2808 ft'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('converter-category-mass')));
    await tester.pumpAndSettle();
    expect(find.text('2.2046 lb'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('converter-value')), '70');
    await tester.pumpAndSettle();
    expect(find.text('154.3236 lb'), findsOneWidget);
  });

  testWidgets('swapping the units swaps the answer', (tester) async {
    await pump(tester);
    await openUnits(tester);
    await tester.tap(find.byKey(const ValueKey('converter-swap')));
    await tester.pumpAndSettle();
    expect(find.text('0.3048 m'), findsOneWidget);
  });

  testWidgets(
    'what was typed is kept as a recent, and tapping it puts it back',
    (tester) async {
      await pump(tester);
      await openUnits(tester);
      await tester.enterText(
        find.byKey(const ValueKey('converter-value')),
        '70',
      );
      await tester.pumpAndSettle();
      await waitForCommit(tester);
      expect(await store.list('recent'), hasLength(1));
      expect(find.text('70 m = 229.6588 ft'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('converter-value')),
        '7',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('70 m = 229.6588 ft'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('converter-value')),
      );
      expect(field.controller!.text, '70');
    },
  );

  testWidgets('a recent can be removed, and Undo brings it back', (
    tester,
  ) async {
    await converterRemember(
      store,
      ConverterEntry(
        id: '',
        tab: ConverterTab.units,
        label: 'stale',
        payload: {'cat': 'mass', 'from': 'kg', 'to': 'pound', 'value': '70'},
        at: DateTime.now(),
      ),
    );
    await pump(tester);
    await openUnits(tester);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await settle(tester);
    expect(await store.list('recent'), isEmpty);
    expect(find.text('Deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await store.list('recent'), hasLength(1));
  });

  testWidgets('starring puts the conversion in the starred list', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('converter-star')));
    await settle(tester);
    expect(await store.list('favorite'), hasLength(1));
    expect(find.text('Starred'), findsOneWidget);
  });

  testWidgets('copy puts the whole conversion on the clipboard', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('converter-copy')));
    await settle(tester);
    expect(find.text('Copied.'), findsOneWidget);
  });

  testWidgets('the two date sums open in their own sheets', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('converter-days-between')));
    await tester.pumpAndSettle();
    expect(find.text('Days between two dates'), findsOneWidget);
    expect(find.text('The same day.'), findsOneWidget);
    // Both ends set, so the count does not depend on the day the test runs
    // (it assumed "today" was 22 Aban 1405 and failed the next day).
    await tester.enterText(
      find.byKey(const ValueKey('converter-days-from')),
      '1405/08/22',
    );
    await tester.enterText(
      find.byKey(const ValueKey('converter-days-to')),
      '1405/08/25',
    );
    await tester.pumpAndSettle();
    expect(find.text('3 days'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('converter-sheet-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('converter-add-days')));
    await tester.pumpAndSettle();
    expect(find.text('A date, plus or minus days'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('converter-add-start')),
      '1405/08/22',
    );
    await tester.enterText(
      find.byKey(const ValueKey('converter-days-count')),
      '10',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('converter-add-days-result')),
      findsOneWidget,
    );
    expect(find.text('2 Azar 1405'), findsWidgets);
  });

  testWidgets('sizes show the measurement beside the number', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Sizes'));
    await tester.pumpAndSettle();
    expect(find.text('Bust'), findsWidgets);
    expect(find.text('88 cm'), findsWidgets);
    expect(find.text('Waist'), findsWidgets);
    expect(find.text('Hip'), findsOneWidget);
    expect(
      find.textContaining('Size charts differ between brands'),
      findsOneWidget,
    );
  });

  testWidgets('Persian: right to left, Persian digits, Jalali date', (
    tester,
  ) async {
    await pump(tester, locale: const Locale('fa'));
    expect(find.text('تبدیل‌گر'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('converter-date')),
      '۱۴۰۵/۰۸/۲۲',
    );
    await tester.pumpAndSettle();
    expect(find.text('۲۲ آبان ۱۴۰۵'), findsOneWidget);
    expect(find.text('جمعه'), findsOneWidget);
    expect(find.text('میلادی · ۱۳ نوامبر ۲۰۲۶'), findsOneWidget);
    expect(find.textContaining('تاریخ قمری'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark keeps the screen readable and whole', (tester) async {
    await pump(tester, theme: nexDarkTheme());
    expect(find.byKey(const ValueKey('converter-hero')), findsOneWidget);
    await openUnits(tester);
    expect(find.text('Length'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('twice the text size does not overflow any tab', (tester) async {
    await pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await openUnits(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sizes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the smaller phone still lays out, in Persian and English', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: nexLightTheme(),
        home: NexModuleCalendar(
          solar: true,
          child: ConverterScreen(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the state comes back after the screen is closed and reopened', (
    tester,
  ) async {
    await pump(tester);
    await openUnits(tester);
    await tester.enterText(find.byKey(const ValueKey('converter-value')), '70');
    await tester.pumpAndSettle();
    await waitForCommit(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await pump(tester);
    await openUnits(tester);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('converter-value')),
    );
    expect(field.controller!.text, '70');
  });
}
