import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/archive_screen.dart';
import 'package:nex_client/modules/habits/habits_screen.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/habits/module.dart';
import 'package:nex_core/nex_core.dart' show nexDisplayDate;

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
    Widget? home,
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
        home: home ?? HabitsScreen(store: store),
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

    testWidgets('all archived, small screen, dark and large — no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = NexModuleStore(harness.services, 'habits');
      await store.put('habit', 'h1', {
        'name': 'کشش صبحگاهی',
        'note': '',
        'schedule': 'daily',
        'target': 1,
        'archived': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await pump(
        tester,
        locale: const Locale('fa'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      expect(
        find.text(
          'همهٔ عادت‌ها بایگانی شده‌اند. یکی را بیرون بیاورید یا تازه‌ای بسازید.',
        ),
        findsOneWidget,
      );
      // Both ways out stay reachable — the state scrolls rather than
      // clipping its buttons off the small screen.
      expect(
        find.byKey(const ValueKey('habits-new')),
        findsOneWidget,
        reason: 'the sheet can still be opened from the empty state',
      );
      // At this scale the state scrolls: bring the second way out on
      // screen — reachability is part of the review.
      await tester.ensureVisible(
        find.byKey(const ValueKey('habits-open-archived')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('habits-open-archived')));
      await tester.pumpAndSettle();
      expect(find.text('کشش صبحگاهی'), findsOneWidget);
      expectNoOverflow(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
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
      // Taking a check-in back says so in Persian, with the shared Undo.
      expect(find.text('ثبت برداشته شد'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('habit-today-h1')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(find.text('۱ از ۱ انجام شد'), findsOneWidget);
      expectNoOverflow(tester);
      // No snackbar timer may outlive the test.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
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

  group('the detail page, calendar dates at the extremes', () {
    Future<void> seedHistory() async {
      final store = NexModuleStore(harness.services, 'habits');
      await store.put('habit', 'h1', {
        'name': 'کشش صبحگاهی',
        'note': 'پنج دقیقه، قبل از قهوه',
        'schedule': 'daily',
        'target': 1,
        'archived': false,
        'createdAt': DateTime.now().toIso8601String(),
      });
      for (final back in [21, 1, 0]) {
        final day = DateTime.now().subtract(Duration(days: back));
        final key = dateKeyOf(day);
        await store.put('check', HabitCheck.idFor('h1', key), {
          'habit': 'h1',
          'date': key,
          'at': day.toIso8601String(),
        });
      }
    }

    for (final locale in [const Locale('fa'), const Locale('en')]) {
      for (final brightness in Brightness.values) {
        testWidgets('history rows with calendar dates, '
            '${locale.languageCode} $brightness at text scale 2.0', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await seedHistory();
          await pump(
            tester,
            locale: locale,
            brightness: brightness,
            textScale: 2.0,
          );
          // The page opens with its hero, which at this scale takes the
          // fold: the habit is reached by scrolling down to it.
          await tester.dragUntilVisible(
            find.text('کشش صبحگاهی'),
            find.byType(ListView).first,
            const Offset(0, -120),
          );
          // Clear of the floating button at the bottom.
          await tester.drag(find.byType(ListView).first, const Offset(0, -200));
          await tester.pumpAndSettle();
          await tester.tap(find.text('کشش صبحگاهی'));
          await tester.pumpAndSettle();

          // The relative words and the calendar day they name, side by
          // side, in the reader's own calendar and digits. At this scale the
          // history lives below the fold, so walk down to it — the walk
          // itself is part of the overflow review.
          final old = DateTime.now().subtract(const Duration(days: 21));
          final expected = nexDisplayDate(
            DateTime(old.year, old.month, old.day),
            solar: locale.languageCode == 'fa',
            persian: locale.languageCode == 'fa',
          );
          final day = find.text(expected);
          await tester.scrollUntilVisible(
            day,
            300,
            scrollable: find.byType(Scrollable).last,
          );
          expect(day, findsOneWidget);
          expect(
            find.text(
              locale.languageCode == 'fa' ? '۲۱ روز پیش' : '21 days ago',
            ),
            findsOneWidget,
          );
          expectNoOverflow(tester);
          // pageBack looks for the English tooltip; the system back gesture
          // is locale-independent.
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        });
      }
    }
  });

  group('the archive screen at the extremes', () {
    testWidgets('empty, Persian dark, text scale 2.0, with its way back', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = NexModuleStore(harness.services, 'habits');
      await pump(
        tester,
        locale: const Locale('fa'),
        brightness: Brightness.dark,
        textScale: 2.0,
        home: ArchiveScreen(store: store),
      );
      expect(
        find.text(
          'هنوز چیزی بایگانی نشده است. هر وقت خواستید، عادتی را از '
          'صفحهٔ خودش بایگانی کنید؛ تاریخچه‌اش می‌ماند.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('habits-archive-back')),
        findsOneWidget,
        reason: 'the empty state carries the action it names',
      );
      expectNoOverflow(tester);
    });

    testWidgets('with one archived habit, English light', (tester) async {
      final store = NexModuleStore(harness.services, 'habits');
      await store.put('habit', 'h1', {
        'name': 'Stretch',
        'note': '',
        'schedule': 'daily',
        'target': 1,
        'archived': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await pump(
        tester,
        locale: const Locale('en'),
        home: ArchiveScreen(store: store),
      );
      expect(find.text('Stretch'), findsOneWidget);
      expect(find.text('Hidden from Today; history kept'), findsOneWidget);
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
      expect(find.text('Check-in removed'), findsOneWidget);
      expectNoOverflow(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
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
