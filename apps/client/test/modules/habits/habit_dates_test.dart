import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/habits/habit_detail_screen.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_core/nex_core.dart' show nexDisplayDate;

import '../../support/nex_harness.dart';

/// The platform calendar is part of the story now: every absolute date the
/// module shows — a check-in's day, the two-week window, the habit's start
/// day — goes through `nexModuleDateLabel`, so a Persian reader sees Jalali
/// with Persian digits and an English reader sees Gregorian, from the same
/// civil storage keys. Relative words stay where they read best.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_habits_cal_'),
  );
  tearDown(() => harness.dispose());

  DateTime civil(int daysBack) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - daysBack);
  }

  String key(int daysBack) => dateKeyOf(civil(daysBack));

  /// The exact string the screen should draw, produced by the same
  /// formatter it uses: outside a `NexModuleCalendar`, Persian falls back to
  /// the Solar Hijri calendar, as the app does for a Persian reader.
  String label(DateTime date, Locale locale) => nexDisplayDate(
    date,
    solar: locale.languageCode == 'fa',
    persian: locale.languageCode == 'fa',
  );

  Future<NexModuleStore> seedHabit({
    String? badCreatedAt,
    List<int> daysBack = const [],
  }) async {
    final store = NexModuleStore(harness.services, 'habits');
    await store.put('habit', 'h1', {
      'name': 'Morning stretch',
      'note': '',
      'schedule': 'daily',
      'target': 1,
      'archived': false,
      'createdAt': badCreatedAt ?? civil(40).toIso8601String(),
    });
    for (final back in daysBack) {
      await store.put('check', HabitCheck.idFor('h1', key(back)), {
        'habit': 'h1',
        'date': key(back),
        'at': civil(back).toIso8601String(),
      });
    }
    return store;
  }

  Future<void> pumpDetail(
    WidgetTester tester,
    NexModuleStore store,
    Locale locale,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HabitDetailScreen(store: store, habitId: 'h1'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('each check-in carries the calendar’s own date, in English', (
    tester,
  ) async {
    final store = await seedHabit(daysBack: [21, 3, 1, 0]);
    await pumpDetail(tester, store, const Locale('en'));

    // Relative words where they read best…
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('3 days ago'), findsOneWidget);
    expect(find.text('21 days ago'), findsOneWidget);
    // …and the platform calendar's absolute day beside every one of them.
    for (final back in [21, 3, 1, 0]) {
      expect(
        find.text(label(civil(back), const Locale('en'))),
        findsOneWidget,
        reason: 'the day $back days back carries its calendar date',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Persian reader sees the same days as Jalali, Persian digits', (
    tester,
  ) async {
    final store = await seedHabit(daysBack: [21, 3, 1, 0]);
    await pumpDetail(tester, store, const Locale('fa'));

    expect(find.text('امروز'), findsOneWidget);
    expect(find.text('دیروز'), findsOneWidget);
    expect(find.text('۳ روز پیش'), findsOneWidget);
    for (final back in [21, 3, 1, 0]) {
      final jalali = label(civil(back), const Locale('fa'));
      expect(
        jalali.contains(RegExp('[0-9]')),
        isFalse,
        reason: 'Persian digits, never Latin ones',
      );
      expect(find.text(jalali), findsOneWidget);
    }
    // The start day line names the Solar Hijri calendar date too.
    expect(
      find.text('شروع از ${label(civil(40), const Locale('fa'))}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the habit’s start day is shown in the same calendar', (
    tester,
  ) async {
    final store = await seedHabit(daysBack: [1]);
    await pumpDetail(tester, store, const Locale('en'));
    expect(
      find.text('Started ${label(civil(40), const Locale('en'))}'),
      findsOneWidget,
    );
  });

  testWidgets(
    'an unknown creation date shows nothing rather than a wrong day',
    (tester) async {
      final store = await seedHabit(badCreatedAt: 'not a date', daysBack: [1]);
      await pumpDetail(tester, store, const Locale('en'));
      expect(find.textContaining('Started'), findsNothing);
    },
  );

  testWidgets('the two-week window names its first and last day', (
    tester,
  ) async {
    final store = await seedHabit(daysBack: [1]);
    await pumpDetail(tester, store, const Locale('en'));
    final range =
        '${label(civil(13), const Locale('en'))} – '
        '${label(civil(0), const Locale('en'))}';
    expect(find.text(range), findsOneWidget);
  });

  testWidgets('and in Persian, with «تا» between the two Jalali days', (
    tester,
  ) async {
    final store = await seedHabit(daysBack: [1]);
    await pumpDetail(tester, store, const Locale('fa'));
    final range =
        '${label(civil(13), const Locale('fa'))} تا '
        '${label(civil(0), const Locale('fa'))}';
    expect(find.text(range), findsOneWidget);
  });

  testWidgets('a single check-in reads in the singular', (tester) async {
    final store = await seedHabit(daysBack: [0]);
    await pumpDetail(tester, store, const Locale('en'));
    expect(find.text('1 check-in'), findsOneWidget);
    expect(find.text('1 check-ins'), findsNothing);
  });

  testWidgets('legacy records that double-wrote a day are counted, honestly', (
    tester,
  ) async {
    final store = await seedHabit();
    // Two raw records for the same civil day — ids the current writer can
    // no longer produce — exactly what an older version could leave behind.
    await store.put('check', 'legacy-a', {
      'habit': 'h1',
      'date': key(5),
      'at': civil(5).toIso8601String(),
    });
    await store.put('check', 'legacy-b', {
      'habit': 'h1',
      'date': key(5),
      'at': civil(5).toIso8601String(),
    });
    await pumpDetail(tester, store, const Locale('en'));

    // The counts see one day; the history says out loud that the day holds
    // two records — once per row.
    expect(find.text('5 days ago'), findsNWidgets(2));
    expect(find.text('2 check-ins'), findsNWidgets(2));
    expect(find.text('1 check-in'), findsOneWidget);
  });
}
