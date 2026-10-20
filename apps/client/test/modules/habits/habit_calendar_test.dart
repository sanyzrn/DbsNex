import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/habits/habit_detail_screen.dart';
import 'package:nex_client/modules/habits/habit_math.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

Habit habit({
  bool weekly = false,
  int target = 3,
  required DateTime createdAt,
}) => Habit(
  id: 'h1',
  name: 'Read',
  note: '',
  weekly: weekly,
  target: weekly ? target : 1,
  archived: false,
  createdAt: createdAt,
);

String key(DateTime d) => dateKeyOf(d);

void main() {
  group('NexModuleMonth: a month in the calendar the reader uses', () {
    test('Mehr 1405 starts on 23 September 2026 and has 30 days', () {
      final month = NexModuleMonth.of(DateTime(2026, 10, 20), solar: true);
      expect((month.year, month.month), (1405, 7));
      expect(month.first, DateTime(2026, 9, 23));
      expect(month.days, 30);
      expect(month.dayAt(30), DateTime(2026, 10, 22));
    });

    test('shifting crosses a year in both directions', () {
      const farvardin = NexModuleMonth(true, 1405, 1);
      expect(farvardin.shift(-1), const NexModuleMonth(true, 1404, 12));
      expect(
        const NexModuleMonth(false, 2026, 12).shift(1),
        const NexModuleMonth(false, 2027, 1),
      );
      expect(farvardin.shift(-1).shift(1), farvardin);
    });

    test('Esfand has its leap day only in a leap year', () {
      expect(const NexModuleMonth(true, 1403, 12).days, 30);
      expect(const NexModuleMonth(true, 1404, 12).days, 29);
    });

    test('leading blanks follow the first day of the week', () {
      // 1 October 2026 is a Thursday.
      const october = NexModuleMonth(false, 2026, 10);
      expect(october.leadingBlanks(DateTime.monday), 3);
      expect(october.leadingBlanks(DateTime.saturday), 5);
      expect(october.leadingBlanks(DateTime.thursday), 0);
    });
  });

  group('completion rate counts only the time the habit existed', () {
    final today = DateTime(2026, 10, 20);

    test('a month-old daily habit: days checked of days since', () {
      final h = habit(createdAt: DateTime(2026, 10, 1));
      final keys = [
        for (var d = 1; d <= 20; d += 2) key(DateTime(2026, 10, d)),
      ];
      final rate = HabitMath.dailyRate(h, keys, today, 30);
      expect((rate.done, rate.possible), (10, 20));
      expect(rate.percent, 50);
    });

    test('a window shorter than the habit counts the window', () {
      final h = habit(createdAt: DateTime(2026, 1, 1));
      final keys = [for (var d = 14; d <= 20; d++) key(DateTime(2026, 10, d))];
      final rate = HabitMath.dailyRate(h, keys, today, 7);
      expect((rate.done, rate.possible), (7, 7));
      expect(rate.percent, 100);
    });

    test('check-ins from before the creation day pull the start back', () {
      final h = habit(createdAt: DateTime(2026, 10, 18));
      final keys = [key(DateTime(2026, 10, 10)), key(DateTime(2026, 10, 20))];
      final rate = HabitMath.dailyRate(h, keys, today, 30);
      expect(rate.possible, 11);
      expect(rate.done, 2);
    });

    test('future check-ins and an unknown start count for nothing', () {
      final h = habit(createdAt: DateTime.fromMillisecondsSinceEpoch(0));
      expect(
        HabitMath.dailyRate(h, [key(DateTime(2026, 11, 1))], today, 30),
        isA<HabitRate>().having((r) => r.possible, 'possible', 0),
      );
      expect(HabitMath.dailyRate(h, const [], today, 30).percent, 0);
    });

    test('weekly: finished weeks that met the target, not the current one', () {
      // Weeks run Saturday to Friday. 20 Oct 2026 is a Tuesday, so the week
      // in progress began on Saturday 17 Oct.
      final h = habit(weekly: true, target: 2, createdAt: DateTime(2026, 9, 1));
      final keys = [
        // week of 3 Oct: two check-ins (met)
        key(DateTime(2026, 10, 3)), key(DateTime(2026, 10, 5)),
        // week of 10 Oct: one (not met)
        key(DateTime(2026, 10, 10)),
        // current week: two, but it is unfinished
        key(DateTime(2026, 10, 17)), key(DateTime(2026, 10, 18)),
      ];
      final rate = HabitMath.weeklyRate(h, keys, today, weeks: 2);
      expect((rate.done, rate.possible), (1, 2));
    });

    test('weekly: a first week that began mid-week is not a miss', () {
      final h = habit(
        weekly: true,
        target: 3,
        createdAt: DateTime(2026, 10, 7),
      );
      final rate = HabitMath.weeklyRate(h, const [], today, weeks: 12);
      // 7 Oct is a Wednesday; the first full week begins Saturday 10 Oct.
      expect(rate.possible, 1);
      expect(rate.done, 0);
    });
  });

  group('the calendar on a habit page', () {
    late NexTestHarness h;
    setUp(() async => h = await NexTestHarness.create(name: 'habcal_'));
    tearDown(() => h.dispose());

    Widget app(NexModuleStore store, {Locale locale = const Locale('en')}) =>
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nexLightTheme(),
          home: HabitDetailScreen(store: store, habitId: 'h1'),
        );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
    }

    /// Scrolls the page until [finder] is on the 800x600 test screen — the
    /// list builds a little beyond the screen, so "found" is not "visible".
    Future<void> reveal(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 12; i++) {
        final y = tester.getCenter(finder).dy;
        if (y > 80 && y < 520) return;
        await tester.drag(
          find.byType(ListView).first,
          Offset(0, y >= 520 ? -300 : 300),
        );
        await tester.pumpAndSettle();
      }
    }

    Future<NexModuleStore> seeded() async {
      final store = NexModuleStore(h.services, 'habits');
      await store.put('habit', 'h1', {
        'name': 'Read',
        'note': '',
        'schedule': 'daily',
        'target': 1,
        'archived': false,
        'createdAt': DateTime.now()
            .subtract(const Duration(days: 40))
            .toIso8601String(),
      });
      return store;
    }

    testWidgets(
      'a tap on an earlier day makes its check-in; again, undoes it',
      (tester) async {
        final store = await seeded();
        await tester.pumpWidget(app(store));
        await settle(tester);
        final now = DateTime.now();
        // The day before yesterday is in this month or the last; go back if it
        // is not on this page.
        final target = now.subtract(const Duration(days: 2));
        final dayKey = key(target);
        if (target.month != now.month) {
          await reveal(
            tester,
            find.byKey(const ValueKey('habit-month-previous')),
          );
          await tester.tap(find.byKey(const ValueKey('habit-month-previous')));
          await tester.pumpAndSettle();
        }
        final finder = find.byKey(ValueKey('habit-day-$dayKey'));
        await reveal(tester, finder);
        await tester.tap(finder);
        await settle(tester);
        expect(await store.get('check', 'h1:$dayKey'), isNotNull);

        await reveal(tester, finder);
        await tester.tap(finder);
        await settle(tester);
        expect(await store.get('check', 'h1:$dayKey'), isNull);
      },
    );

    testWidgets('a day to come cannot be marked', (tester) async {
      final store = await seeded();
      await tester.pumpWidget(app(store));
      await settle(tester);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      if (tomorrow.month == DateTime.now().month) {
        final finder = find.byKey(ValueKey('habit-day-${key(tomorrow)}'));
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await settle(tester);
        expect(await store.get('check', 'h1:${key(tomorrow)}'), isNull);
      }
      // The month after this one is not reachable at all.
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('habit-month-next')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('in Persian the month is Jalali, in Persian digits', (
      tester,
    ) async {
      final store = await seeded();
      await tester.pumpWidget(app(store, locale: const Locale('fa')));
      await settle(tester);
      final title = tester.widget<Text>(
        find.byKey(const ValueKey('habit-month-title')),
      );
      expect(title.data, matches(RegExp(r'^[^\d]+ [۰-۹]{4}$')));
      expect(title.data, contains('۱۴'));
    });
  });
}
