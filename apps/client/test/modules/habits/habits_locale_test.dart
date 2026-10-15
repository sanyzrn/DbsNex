import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/habits_screen.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/habits/module.dart';

import '../../support/nex_harness.dart';

/// The habits screen in Persian right-to-left and English left-to-right,
/// light and dark, at text scale 1.0 and 2.0, and with animations off:
/// nothing overflows, nothing reads the wrong way round, and numbers come
/// out in the locale's own digits.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_habits_l10n_'),
  );
  tearDown(() => harness.dispose());

  Future<void> seed() async {
    final store = NexModuleStore(harness.services, 'habits');
    await store.put('habit', 'h1', {
      'name': 'کشش صبحگاهی',
      'note': 'پنج دقیقه، قبل از قهوه',
      'schedule': 'daily',
      'target': 1,
      'archived': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
    final today = dateKeyOf(DateTime.now());
    await store.put('check', HabitCheck.idFor('h1', today), {
      'habit': 'h1',
      'date': today,
      'at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    required Locale locale,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) async {
    final store = NexModuleStore(harness.services, 'habits');
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: HabitsScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoOverflow(WidgetTester tester) {
    final exception = tester.takeException();
    expect(exception, isNull, reason: 'no overflow, nothing clipped');
  }

  group('Persian, right to left', () {
    testWidgets('light, with Persian digits', (tester) async {
      await seed();
      await pump(tester, locale: const Locale('fa'));
      expect(
        (find.byType(Directionality).evaluate().single.widget as Directionality)
            .textDirection,
        TextDirection.rtl,
      );
      expect(find.text('عادت‌ها'), findsOneWidget);
      expect(find.text('امروز'), findsOneWidget);
      expect(
        find.text('۱ از ۱ انجام شد'),
        findsOneWidget,
        reason: 'numbers in Persian digits',
      );
      expectNoOverflow(tester);
    });

    testWidgets('dark, at text scale 2.0', (tester) async {
      await seed();
      await pump(
        tester,
        locale: const Locale('fa'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      expect(find.text('عادت‌ها'), findsOneWidget);
      expect(find.text('۱ از ۱ انجام شد'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('the empty state, dark and large', (tester) async {
      await pump(
        tester,
        locale: const Locale('fa'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      expect(
        find.text('هنوز عادتی نیست. با یک چیز کوچک شروع کنید.'),
        findsOneWidget,
      );
      expectNoOverflow(tester);
    });

    testWidgets('checking in and out, in Persian', (tester) async {
      await seed();
      await pump(tester, locale: const Locale('fa'));
      await tester.tap(find.byKey(const ValueKey('habit-today-h1')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(find.text('۰ از ۱ انجام شد'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('habit-today-h1')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(find.text('۱ از ۱ انجام شد'), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  group('English, left to right', () {
    testWidgets('light', (tester) async {
      await seed();
      await pump(tester, locale: const Locale('en'));
      expect(
        (find.byType(Directionality).evaluate().single.widget as Directionality)
            .textDirection,
        TextDirection.ltr,
      );
      expect(find.text('Habits'), findsOneWidget);
      expect(find.text('1 of 1 done'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('dark, at text scale 2.0', (tester) async {
      await seed();
      await pump(
        tester,
        locale: const Locale('en'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      expect(find.text('1 of 1 done'), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  group('reduced motion', () {
    testWidgets('with animations off, everything settles at once', (
      tester,
    ) async {
      await seed();
      await pump(tester, locale: const Locale('en'), disableAnimations: true);
      await tester.tap(find.byKey(const ValueKey('habit-today-h1')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(find.text('0 of 1 done'), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  testWidgets('the module’s own words are complete in both languages', (
    tester,
  ) async {
    expect(habitsStrings.en.keys.toSet(), habitsStrings.fa.keys.toSet());
    for (final value in habitsStrings.fa.values) {
      expect(value.trim(), isNotEmpty);
    }
    expect(
      habitsStrings.text(
        lookupAppLocalizations(const Locale('fa')),
        'weekProgress',
        {'done': 1, 'target': 3},
      ),
      '۱ از ۳ این هفته',
    );
  });
}
