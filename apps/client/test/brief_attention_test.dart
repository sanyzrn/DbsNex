import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations_en.dart';
import 'package:nex_client/l10n/app_localizations_fa.dart';
import 'package:nex_client/modules/habits/habit_brief.dart';
import 'package:nex_client/modules/habits/habit_math.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/nex_harness.dart';

void main() {
  ({Habit habit, HabitStanding standing}) row(
    String name, {
    bool weekly = false,
    bool done = false,
    int count = 0,
  }) => (
    habit: Habit.fromBody(name, {
      'name': name,
      'schedule': weekly ? 'weekly' : 'daily',
      'target': 3,
      'goal': 8,
    }),
    standing: HabitStanding(
      streak: 1,
      graceNow: false,
      graceInside: false,
      todayDone: done,
      weekCount: count,
      total: count,
      recent: const [],
      todayAmount: done ? 8 : 2,
    ),
  );

  for (final persian in [false, true]) {
    test(
      'completed daily goals are suppressed, weekly achievements grouped: $persian',
      () {
        final water = persian ? 'آب' : 'Water';
        final reading = persian ? 'مطالعه' : 'Reading';
        final sport = persian ? 'ورزش' : 'Sport';
        final walk = persian ? 'پیاده‌روی' : 'Walk';
        final habits = HabitsBrief([
          row(reading),
          row(water, done: true),
          row(sport, weekly: true, done: true, count: 3),
          row(walk, weekly: true, done: true, count: 3),
        ]);
        final l10n = persian ? AppLocalizationsFa() : AppLocalizationsEn();
        final focused = habits.localText(l10n);
        expect(focused, isNot(contains(water)));
        expect(focused.split('\n'), hasLength(2));
        expect(focused.split('\n').first, contains(reading));
        expect(
          focused.split('\n').last,
          allOf(contains(sport), contains(walk)),
        );
        expect(habits.localText(l10n, includeCompleted: true), contains(water));
        expect(
          habits.source,
          allOf(
            contains(water),
            contains('doneToday'),
            contains('weekGoalMet'),
          ),
        );
      },
    );
  }

  testWidgets(
    'Report keeps overdue work and an important note ahead of a completed daily goal',
    (tester) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      await h.preferences.setBriefStyle(NexBriefStyle.report);
      await h.preferences.setBriefLength(NexBriefLength.medium);
      await h.preferences.setBriefUseHabits(true);
      await h.preferences.setModuleOn('habits', true);
      final now = DateTime.now();
      final titles = ['Call bank', 'Submit report', 'Renew account'];
      for (final title in titles) {
        final note = await h.services.captureText(title);
        await h.db.setDueAt(note!.id, now.subtract(const Duration(hours: 2)));
      }
      await h.services.captureText('Important launch decision');
      final store = NexModuleStore(h.services, 'habits');
      await store.put('habit', 'water', {
        'name': 'Completed water goal',
        'schedule': 'daily',
        'goal': 8,
        'createdAt': now.toIso8601String(),
      });
      final day = dateKeyOf(now);
      await store.put('check', HabitCheck.idFor('water', day), {
        'habit': 'water',
        'date': day,
        'amount': 8,
        'at': now.toIso8601String(),
      });
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('timeline-recap'));
      final text = tester
          .widgetList<Text>(
            find.descendant(of: panel, matching: find.byType(Text)),
          )
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join('\n');
      for (final title in [...titles, 'Important launch decision']) {
        expect(text, contains(title));
      }
      expect(text, isNot(contains('Completed water goal')));
      expect(h.preferences.aiDaySummaryAt, isNull);
      expect(h.preferences.briefUseHabits, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
