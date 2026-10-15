import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/maintenance/maintenance_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// The Maintenance screens, end to end over a real store: the home
/// groups, adding an asset and an interval, logging services with a
/// cost and a reading, repeat-last, deletion with Undo, archiving,
/// persistence — and Persian RTL, dark, small screens and 2.0 text.
void main() {
  late NexTestHarness harness;
  late NexModuleStore store;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_mnw_');
    store = NexModuleStore(harness.services, 'maintenance');
  });

  tearDown(() async => harness.dispose());

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
          child: MaintenanceScreen(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addAsset(
    WidgetTester tester, {
    String name = 'My car',
    bool persian = false,
  }) async {
    await tester.tap(find.byKey(const ValueKey('maintenance-add-asset')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('maintenance-nickname')),
      name,
    );
    // Count kilometres, as a car does — in the sheet's own language,
    // scrolled into reach on a small phone.
    final odometer = find.descendant(
      of: find.byKey(const ValueKey('maintenance-meterkind')),
      matching: find.text(persian ? 'کیلومترشمار' : 'Odometer'),
    );
    await tester.ensureVisible(odometer);
    await tester.pumpAndSettle();
    await tester.ensureVisible(odometer);
    await tester.tap(odometer);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('maintenance-asset-save')));
    await tester.pumpAndSettle();
  }

  Future<void> addRule(
    WidgetTester tester, {
    required String task,
    String months = '6',
  }) async {
    // From the asset page's Intervals row.
    await tester.tap(find.text('New interval'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('maintenance-rule-task')),
      task,
    );
    // Days is the sheet's default; this rule counts months.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('maintenance-timemode')),
        matching: find.text('Months'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('maintenance-rule-time')),
      months,
    );
    await tester.tap(find.byKey(const ValueKey('maintenance-rule-save')));
    await tester.pumpAndSettle();
  }

  Future<void> logService(
    WidgetTester tester, {
    required String task,
    String? meter,
    String? cost,
  }) async {
    await tester.tap(find.byKey(const ValueKey('maintenance-log-service')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('maintenance-task')),
      task,
    );
    if (meter != null) {
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-meter')),
        meter,
      );
    }
    if (cost != null) {
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-cost')),
        cost,
      );
      // Choosing a currency reveals the IRR unit toggle.
      await tester.tap(find.byKey(const ValueKey('maintenance-pick-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IRR'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('maintenance-event-save')));
    await tester.pumpAndSettle();
  }

  group('the home screen', () {
    testWidgets('empty state says what to do, with the button to do it', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Nothing tracked yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('maintenance-add-asset')),
        findsOneWidget,
      );
      await addAsset(tester);
      expect(find.text('My car'), findsOneWidget);
      // No rules yet: the no-schedule group.
      expect(find.text('No schedule · 1'), findsOneWidget);
    });

    testWidgets('due now and coming up are grouped from real services', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addAsset(tester);
      // Open the asset page.
      await tester.tap(find.text('My car'));
      await tester.pumpAndSettle();
      await addRule(tester, task: 'oil change', months: '6');
      await logService(tester, task: 'oil change', meter: '100000');
      // Service logged today, due in 6 months: scheduled, not due.
      expect(find.text('oil change'), findsAtLeast(1));
      expect(find.textContaining('Due'), findsAtLeast(1));
      // Back to home: the asset sits in Scheduled (nothing due).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Scheduled · 1'), findsOneWidget);
    });

    testWidgets('no meter entered says the distance due is unknown', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addAsset(tester);
      await tester.tap(find.text('My car'));
      await tester.pumpAndSettle();
      // A km rule with no reading ever entered.
      await tester.tap(find.text('New interval'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-rule-task')),
        'oil change',
      );
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-rule-time')),
        '6',
      );
      // Add a usage interval too (the asset counts km): the row
      // labelled "Or every", not the time switch above it.
      await tester.tap(find.text('Or every'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-rule-usage')),
        '10000',
      );
      await tester.tap(find.byKey(const ValueKey('maintenance-rule-save')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Enter a service reading for this task to establish its interval baseline',
        ),
        findsOneWidget,
      );
      // Home: needs information, never "everything is fine".
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Needs information · 1'), findsOneWidget);
    });
  });

  group('the asset page', () {
    testWidgets(
      'log a service with a cost and a reading; costs sum per currency',
      (tester) async {
        await pumpScreen(tester);
        await addAsset(tester);
        await tester.tap(find.text('My car'));
        await tester.pumpAndSettle();
        await logService(
          tester,
          task: 'oil change',
          meter: '100000',
          cost: '1500',
        );
        expect(find.text('oil change'), findsAtLeast(1));
        expect(find.text('1,500 IRR'), findsAtLeast(1));
        // The row's subtitle joins date and reading with a middle dot.
        expect(find.textContaining('100,000 km at service'), findsOneWidget);
        expect(find.textContaining('Today'), findsOneWidget);
        // The cost summary panel appears with its note.
        expect(find.text('Costs entered'), findsOneWidget);
        expect(
          find.text('Only the costs you typed in — nothing inferred'),
          findsOneWidget,
        );
      },
    );

    testWidgets('repeat last service prefills the editor', (tester) async {
      await pumpScreen(tester);
      await addAsset(tester);
      await tester.tap(find.text('My car'));
      await tester.pumpAndSettle();
      await logService(
        tester,
        task: 'oil change',
        meter: '98000',
        cost: '1200',
      );
      await tester.tap(find.byKey(const ValueKey('maintenance-repeat')));
      await tester.pumpAndSettle();
      final task = tester.widget<TextField>(
        find.byKey(const ValueKey('maintenance-task')),
      );
      expect(task.controller!.text, 'oil change');
      final meter = tester.widget<TextField>(
        find.byKey(const ValueKey('maintenance-meter')),
      );
      expect(meter.controller!.text, isEmpty);
      final cost = tester.widget<TextField>(
        find.byKey(const ValueKey('maintenance-cost')),
      );
      expect(cost.controller!.text, '1200');
    });

    testWidgets('delete a service asks and Undo restores it', (tester) async {
      await pumpScreen(tester);
      await addAsset(tester);
      await tester.tap(find.text('My car'));
      await tester.pumpAndSettle();
      await logService(tester, task: 'oil change', meter: '50000');
      // Open the event from the timeline.
      await tester.tap(find.text('oil change').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('maintenance-event-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this service?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Deleted'), findsOneWidget);
      expect(find.text('No services logged yet'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('oil change'), findsAtLeast(1));
    });

    testWidgets('archive moves the asset out of the overview', (tester) async {
      await pumpScreen(tester);
      await addAsset(tester);
      await tester.tap(find.text('My car'));
      await tester.pumpAndSettle();
      // The page's menu: archive.
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();
      expect(find.text('Archive this asset?'), findsOneWidget);
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();
      // Back on home: the archived group holds it.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Archived · 1'), findsOneWidget);
      expect(find.text('My car'), findsOneWidget);
    });
  });

  group('persistence and the platform contract', () {
    testWidgets('everything survives reopening the screen', (tester) async {
      await pumpScreen(tester);
      await addAsset(tester);
      await tester.tap(find.text('My car'));
      await tester.pumpAndSettle();
      await logService(tester, task: 'oil change', meter: '12000', cost: '300');
      await pumpScreen(tester);
      await tester.tap(find.text('My car'));
      await tester.pumpAndSettle();
      expect(find.text('oil change'), findsAtLeast(1));
      expect(find.text('300 IRR'), findsAtLeast(1));
    });
  });

  group('languages, themes and sizes', () {
    testWidgets('Persian reads right to left with Persian words', (
      tester,
    ) async {
      await pumpScreen(tester, locale: const Locale('fa'));
      expect(find.text('هنوز چیزی ثبت نشده'), findsOneWidget);
      await addAsset(tester, name: 'خودم', persian: true);
      expect(find.text('خودم'), findsOneWidget);
      expect(find.text('بدون برنامه · ۱'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('خودم'))),
        TextDirection.rtl,
      );
    });

    testWidgets('dark theme keeps every label legible', (tester) async {
      await pumpScreen(tester, dark: true);
      await addAsset(tester);
      expect(find.text('My car'), findsOneWidget);
      expect(find.text('No schedule · 1'), findsOneWidget);
    });

    testWidgets('a small screen scrolls instead of overflowing', (
      tester,
    ) async {
      await pumpScreen(tester, size: const Size(360, 640));
      await addAsset(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('My car'), findsOneWidget);
    });

    testWidgets('text at 2.0 scale still lays out', (tester) async {
      await pumpScreen(tester, textScale: 2.0, size: const Size(400, 1800));
      await addAsset(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('No schedule · 1'), findsOneWidget);
    });
  });
}
