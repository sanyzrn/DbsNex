import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/smoke_free_screen.dart';

import '../../support/nex_harness.dart';

/// The words the module says out loud: English singulars that a bare
/// "{n} days" template would get wrong, the Persian equivalents, the honest
/// same-day attempt line, and an empty-state button that grows with the
/// words instead of clipping at 2× text.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_smoke_words_'),
  );
  tearDown(() => harness.dispose());

  Future<NexModuleStore> pump(
    WidgetTester tester, {
    required Locale locale,
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
  }) async {
    final store = NexModuleStore(harness.services, 'smoke_free');
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: SmokeFreeScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> seedActive(
    NexModuleStore store, {
    int perDay = 1,
    int price = 0,
  }) => store.put('quit', 'q1', {
    'startedAt': DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String(),
    'cigarettesPerDay': perDay,
    'pricePerPackMinor': price,
    'currency': 'IRR',
    'perPack': 20,
    'endedAt': null,
    'endedWhy': null,
  });

  testWidgets('one smoke-free day and one cigarette read in the singular', (
    tester,
  ) async {
    final store = await pump(tester, locale: const Locale('en'));
    await seedActive(store, perDay: 1);
    await tester.pumpAndSettle();

    expect(find.text('Smoke-free for 1 day'), findsOneWidget);
    expect(find.text('≈ 1 cigarette not smoked'), findsOneWidget);
    expect(find.text('Smoke-free for 1 days'), findsNothing);
    expect(find.text('≈ 1 cigarettes not smoked'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same one-day dashboard in Persian', (tester) async {
    final store = await pump(tester, locale: const Locale('fa'));
    await seedActive(store, perDay: 1);
    await tester.pumpAndSettle();

    expect(find.text('۱ روز بدون سیگار'), findsOneWidget);
    expect(find.text('حدود ۱ سیگار نکشیده شده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a one-day attempt lasts in the singular', (tester) async {
    final now = DateTime.now();
    final store = await pump(tester, locale: const Locale('en'));
    await store.put('quit', 'q1', {
      // Noon two days ago to noon yesterday: one calendar day at any hour of
      // the day the test runs (now-1h crossed midnight before 01:00).
      'startedAt': DateTime(
        now.year,
        now.month,
        now.day - 2,
        12,
      ).toIso8601String(),
      'cigarettesPerDay': 10,
      'pricePerPackMinor': 0,
      'perPack': 20,
      'endedAt': DateTime(
        now.year,
        now.month,
        now.day - 1,
        12,
      ).toIso8601String(),
      'endedWhy': 'lapse',
    });
    await tester.pumpAndSettle();

    expect(find.text('Lasted 1 day'), findsOneWidget);
    expect(find.text('Lasted 1 days'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a one-day attempt in Persian history', (tester) async {
    final now = DateTime.now();
    final store = await pump(tester, locale: const Locale('fa'));
    await store.put('quit', 'q1', {
      // Noon two days ago to noon yesterday: one calendar day at any hour of
      // the day the test runs (now-1h crossed midnight before 01:00).
      'startedAt': DateTime(
        now.year,
        now.month,
        now.day - 2,
        12,
      ).toIso8601String(),
      'cigarettesPerDay': 10,
      'pricePerPackMinor': 0,
      'perPack': 20,
      'endedAt': DateTime(
        now.year,
        now.month,
        now.day - 1,
        12,
      ).toIso8601String(),
      'endedWhy': 'lapse',
    });
    await tester.pumpAndSettle();

    expect(find.text('۱ روز دوام آورد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a same-day attempt is said out loud, not as zero days', (
    tester,
  ) async {
    // Two fixed times on one calendar day (yesterday), not "two hours ago":
    // run between midnight and 02:00 that crossed into the next day, and the
    // attempt was rightly one day long. The nightly run is at 01:39 UTC.
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day - 1);
    final store = await pump(tester, locale: const Locale('en'));
    await store.put('quit', 'q1', {
      'startedAt': DateTime(day.year, day.month, day.day, 10).toIso8601String(),
      'cigarettesPerDay': 10,
      'pricePerPackMinor': 0,
      'perPack': 20,
      'endedAt': DateTime(day.year, day.month, day.day, 12).toIso8601String(),
      'endedWhy': 'lapse',
    });
    await tester.pumpAndSettle();

    expect(find.text('Ended on the day it started'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a craving stamped tomorrow reads as Tomorrow', (tester) async {
    final now = DateTime.now();
    final store = await pump(tester, locale: const Locale('en'));
    await store.put('craving', 'c1', {
      'at': now.add(const Duration(days: 1)).toIso8601String(),
      'intensity': 2,
      'triggers': ['stress'],
      'coping': null,
      'note': '',
    });
    await tester.pumpAndSettle();

    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('In 1 days'), findsNothing);
    expect(find.textContaining('days ago'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tomorrow and the day after in Persian', (tester) async {
    final now = DateTime.now();
    final store = await pump(tester, locale: const Locale('fa'));
    await store.put('craving', 'c1', {
      'at': now.add(const Duration(days: 1)).toIso8601String(),
      'intensity': 2,
      'triggers': ['stress'],
      'coping': null,
      'note': '',
    });
    await store.put('craving', 'c2', {
      'at': now.add(const Duration(days: 2)).toIso8601String(),
      'intensity': 1,
      'triggers': [],
      'coping': null,
      'note': '',
    });
    await tester.pumpAndSettle();

    expect(find.text('فردا'), findsOneWidget);
    expect(find.text('۲ روز دیگر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two days ahead stays the honest plural in English', (
    tester,
  ) async {
    final now = DateTime.now();
    final store = await pump(tester, locale: const Locale('en'));
    await store.put('craving', 'c1', {
      'at': now.add(const Duration(days: 2)).toIso8601String(),
      'intensity': 2,
      'triggers': ['stress'],
      'coping': null,
      'note': '',
    });
    await tester.pumpAndSettle();

    expect(find.text('In 2 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the empty-state start button grows past 40 px at 2× text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester, locale: const Locale('en'), textScale: 2.0);

    final button =
        tester.renderObject(find.byKey(const ValueKey('smoke-start')))
            as RenderBox;
    expect(
      button.size.height,
      greaterThan(40),
      reason:
          'Material caps a filled button at 40 px unless the maximum '
          'height is lifted; at 2× text that cap clips the label',
    );
    expect(tester.takeException(), isNull);
  });
}
