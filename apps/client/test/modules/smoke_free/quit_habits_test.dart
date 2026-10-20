import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/quit_habits.dart';
import 'package:nex_client/modules/smoke_free/quit_home_screen.dart';
import 'package:nex_client/modules/smoke_free/quit_model.dart';
import 'package:nex_client/modules/smoke_free/smoke_free_screen.dart';
import 'package:nex_client/modules/smoke_free/smoke_math.dart';

import '../../support/nex_harness.dart';

/// Quit Habits: several habits, each its own count; the records of the
/// module as it was (cigarettes only) read exactly as before.
void main() {
  group('the model', () {
    test(
      'a record from before Quit Habits is cigarettes, written the same',
      () {
        final legacy = QuitAttempt.fromBody('q1', {
          'startedAt': '2026-10-01T09:00:00.000',
          'cigarettesPerDay': 10,
          'v': 2,
          'pricePerPackMinor': 650,
          'currency': 'USD',
          'currencyDecimals': 2,
          'perPack': 20,
          'endedAt': null,
          'endedWhy': null,
        });
        expect(legacy.habit, 'cigarette');
        expect(legacy.key, 'cigarette');
        final json = legacy.toJson();
        expect(json['v'], 2);
        expect(json.containsKey('habit'), isFalse);
        expect(json.containsKey('why'), isFalse);
      },
    );

    test(
      'another habit, its reason, goal and minutes survive a round trip',
      () {
        final a = QuitAttempt.fromBody('q2', {
          'startedAt': '2026-10-01T09:00:00.000',
          'cigarettesPerDay': 3,
          'pricePerPackMinor': 400,
          'currency': 'USD',
          'currencyDecimals': 2,
          'perPack': 1,
          'habit': 'caffeine',
          'why': 'Sleep better',
          'goalMinor': 10000,
          'minutesPerUnit': 5,
        });
        final again = QuitAttempt.fromBody('q2', a.toJson());
        expect(again.habit, 'caffeine');
        expect(again.why, 'Sleep better');
        expect(again.goalMinor, 10000);
        expect(again.minutesPerUnit, 5);
        expect(a.toJson()['v'], 3);
      },
    );

    test('a custom habit is told by its name, however it is written', () {
      expect(
        quitHabitKey('custom', ' Nail  Biting '),
        quitHabitKey('custom', 'nail biting'),
      );
      expect(quitHabitKey('custom', 'a'), isNot(quitHabitKey('custom', 'b')));
    });

    test('a craving with no habit belongs to cigarettes', () {
      expect(
        Craving.fromBody('c', {'at': '2026-10-01T10:00:00.000'}).habit,
        'cigarette',
      );
      expect(
        Craving.fromBody('c', {
          'at': '2026-10-01T10:00:00.000',
          'habit': 'alcohol',
        }).toJson()['habit'],
        'alcohol',
      );
    });

    test('one entry per habit, the running attempt first', () {
      QuitAttempt a(
        String id,
        String habit,
        DateTime start, {
        bool ended = false,
      }) => QuitAttempt(
        id: id,
        startedAt: start,
        cigarettesPerDay: 1,
        perPack: 1,
        endedAt: ended ? start.add(const Duration(days: 1)) : null,
        endedWhy: ended ? 'lapse' : null,
        habit: habit,
      );
      final now = DateTime(2026, 10, 20);
      final habits = quitHabitsOf([
        a('1', 'alcohol', now.subtract(const Duration(days: 9)), ended: true),
        a('2', 'alcohol', now.subtract(const Duration(days: 3))),
        a('3', 'caffeine', now.subtract(const Duration(days: 5)), ended: true),
        a('4', 'vape', now.subtract(const Duration(days: 1))),
      ]);
      expect(habits.map((h) => h.id), ['4', '2', '3']);
    });

    test('elapsed time reads in days, hours and minutes, never below zero', () {
      final e = QuitElapsed.between(
        DateTime(2026, 10, 1, 9, 0),
        DateTime(2026, 10, 3, 11, 25),
      );
      expect((e.days, e.hours, e.minutes), (2, 2, 25));
      final future = QuitElapsed.between(
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 3),
      );
      expect((future.days, future.hours, future.minutes), (0, 0, 0));
    });

    test('marks reached and the next one', () {
      final r = quitMilestonesAt(10, quitMilestones);
      expect(r.earned, [1, 3, 7]);
      expect(r.next, 14);
      expect(quitMilestonesAt(400, quitMilestones).next, isNull);
    });
  });

  group('the pages', () {
    late NexTestHarness h;
    setUp(() async => h = await NexTestHarness.create(name: 'nex_quit_'));
    tearDown(() => h.dispose());

    Widget app(Widget home, {Locale locale = const Locale('en')}) =>
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nexLightTheme(),
          home: home,
        );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
    }

    String iso(int daysAgo) =>
        DateTime.now().subtract(Duration(days: daysAgo)).toIso8601String();

    testWidgets('an empty module offers one way in', (tester) async {
      final store = NexModuleStore(h.services, 'smoke_free');
      await tester.pumpWidget(app(QuitHomeScreen(store: store)));
      await settle(tester);
      expect(find.byKey(const ValueKey('quit-add')), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('habits are listed, each opening its own page', (tester) async {
      final store = NexModuleStore(h.services, 'smoke_free');
      await store.put('quit', 'a', {
        'startedAt': iso(10),
        'cigarettesPerDay': 10,
        'pricePerPackMinor': 650,
        'currency': 'USD',
        'currencyDecimals': 2,
        'perPack': 20,
        'v': 2,
      });
      await store.put('quit', 'b', {
        'startedAt': iso(3),
        'cigarettesPerDay': 2,
        'pricePerPackMinor': 300,
        'currency': 'USD',
        'currencyDecimals': 2,
        'perPack': 1,
        'habit': 'alcohol',
        'why': 'Mornings',
        'v': 3,
      });
      await tester.pumpWidget(app(QuitHomeScreen(store: store)));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('quit-habit-cigarette')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('quit-habit-alcohol')), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quit-habit-alcohol')));
      await settle(tester);
      expect(find.text('3 days without alcohol'), findsOneWidget);
      expect(find.byKey(const ValueKey('quit-counter')), findsOneWidget);
      expect(find.byKey(const ValueKey('quit-why')), findsOneWidget);
      expect(find.byKey(const ValueKey('sos-open')), findsOneWidget);
    });

    testWidgets('a craving belongs to the habit it was logged for', (
      tester,
    ) async {
      final store = NexModuleStore(h.services, 'smoke_free');
      await store.put('quit', 'a', {
        'startedAt': iso(4),
        'cigarettesPerDay': 2,
        'pricePerPackMinor': 300,
        'currency': 'USD',
        'currencyDecimals': 2,
        'perPack': 1,
        'habit': 'alcohol',
        'v': 3,
      });
      await store.put('craving', 'c1', {
        'at': iso(1),
        'intensity': 3,
        'triggers': ['stress'],
        'habit': 'alcohol',
      });
      await store.put('craving', 'c2', {
        'at': iso(1),
        'intensity': 1,
        'triggers': ['boredom'],
      });
      await tester.pumpWidget(
        app(SmokeFreeScreen(store: store, habit: 'alcohol')),
      );
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Overwhelming · Stress'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Overwhelming · Stress'), findsOneWidget);
      expect(find.text('Light · Boredom'), findsNothing);
    });

    testWidgets('the help sheet: breathing, waiting, tips, the reason', (
      tester,
    ) async {
      final store = NexModuleStore(h.services, 'smoke_free');
      await store.put('quit', 'a', {
        'startedAt': iso(2),
        'cigarettesPerDay': 5,
        'pricePerPackMinor': 100,
        'currency': 'USD',
        'currencyDecimals': 2,
        'perPack': 1,
        'habit': 'caffeine',
        'why': 'Sleep',
        'v': 3,
      });
      await tester.pumpWidget(
        app(SmokeFreeScreen(store: store, habit: 'caffeine')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('sos-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sos-why')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sos-breath-toggle')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('sos-breath-count')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sos-breath-toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wait'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sos-wait-start')));
      await tester.pump(const Duration(seconds: 61));
      expect(find.text('08:59 left'), findsOneWidget);
      await tester.pump(const Duration(minutes: 9));
      expect(find.byKey(const ValueKey('sos-wait-done')), findsOneWidget);

      await tester.tap(find.text('Distract'));
      await tester.pumpAndSettle();
      expect(find.text('Drink a glass of water slowly.'), findsOneWidget);
    });

    testWidgets('a habit that starts later says so, not a count', (
      tester,
    ) async {
      final store = NexModuleStore(h.services, 'smoke_free');
      await store.put('quit', 'a', {
        'startedAt': DateTime.now()
            .add(const Duration(days: 5))
            .toIso8601String(),
        'cigarettesPerDay': 5,
        'pricePerPackMinor': 0,
        'currency': 'USD',
        'currencyDecimals': 2,
        'perPack': 1,
        'habit': 'sugar',
        'v': 3,
      });
      await tester.pumpWidget(
        app(SmokeFreeScreen(store: store, habit: 'sugar')),
      );
      await settle(tester);
      expect(find.textContaining('Starts in'), findsWidgets);
      expect(find.textContaining('days without'), findsNothing);
    });

    testWidgets('adding a habit starts with what it is', (tester) async {
      final store = NexModuleStore(h.services, 'smoke_free');
      await tester.pumpWidget(app(QuitHomeScreen(store: store)));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('quit-add')));
      await tester.pumpAndSettle();
      for (final key in ['cigarette', 'alcohol', 'custom']) {
        expect(find.byKey(ValueKey('quit-preset-$key')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('quit-preset-alcohol')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quit-safety')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quit-preset-custom')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quit-field-name')), findsOneWidget);
    });
  });
}
