import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/cycle_summary.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// The assistant reads «Cycle» only when it has been allowed to, and then
/// a summary — never the day notes.
void main() {
  test('the assistant can ask for the cycle, as a read', () {
    final action = parseAssistantActions(
      '```nex\n{"action": "cycle"}\n```',
    ).single;
    expect(action.kind, AssistantActionKind.cycle);
    expect(action.isRead, isTrue);
  });

  group('the summary', () {
    late NexTestHarness harness;

    setUp(() async {
      harness = await NexTestHarness.create(
        name: 'nex_cycle_ai_',
        preferences: {'cycle.set_up': true},
      );
      final now = DateTime.now();
      final last = DateTime(now.year, now.month, now.day - 10);
      for (var k = 3; k >= 0; k--) {
        final start = last.subtract(Duration(days: 29 * k));
        final p = await harness.services.cycleStartPeriod(start);
        await harness.services.cycleEndPeriod(
          p.id,
          start.add(const Duration(days: 4)),
        );
      }
      await harness.services.cycleSaveDay(
        CycleDayLog(
          day: CycleDate.of(last),
          symptoms: {CycleSymptom.cramps},
          note: 'private words about my body',
        ),
      );
    });

    tearDown(() => harness.dispose());

    test('is "not shared" until the person allows it', () async {
      final text = await nexCycleSummaryForAssistant(
        services: harness.services,
        preferences: harness.preferences,
      );
      expect(text, contains('not shared'));
      expect(text, isNot(contains('Next period')));
    });

    test('once allowed, says where the cycle is — and no day notes', () async {
      await harness.preferences.setCycleAssistantAccess(true);
      final text = await nexCycleSummaryForAssistant(
        services: harness.services,
        preferences: harness.preferences,
      );
      expect(text, contains('Cycle day 11'));
      expect(text, contains('Next period: likely'));
      expect(text, contains('cramps ×1'));
      expect(text, isNot(contains('private words')));
    });

    test('fertility signs of this cycle are included', () async {
      await harness.preferences.setCycleAssistantAccess(true);
      final now = DateTime.now();
      await harness.services.cycleSaveDay(
        CycleDayLog(
          day: CycleDate.of(DateTime(now.year, now.month, now.day - 1)),
          temperature: 36.7,
          ovulationTest: CycleOvulationTest.positive,
          mucus: CycleMucus.eggWhite,
        ),
      );
      final text = await nexCycleSummaryForAssistant(
        services: harness.services,
        preferences: harness.preferences,
      );
      expect(text, contains('Fertility signs this cycle:'));
      expect(text, contains('36.70°C ovulation test positive mucus eggWhite'));
    });

    test('turning Cycle off takes it away again', () async {
      await harness.preferences.setCycleAssistantAccess(true);
      await harness.preferences.setCycleEnabled(false);
      final text = await nexCycleSummaryForAssistant(
        services: harness.services,
        preferences: harness.preferences,
      );
      expect(text, contains('not shared'));
    });
  });

  group('gentle companion', () {
    late NexTestHarness harness;
    late DateTime last;

    setUp(() async {
      harness = await NexTestHarness.create(
        name: 'nex_cycle_gentle_',
        preferences: {'cycle.set_up': true},
      );
      final now = DateTime.now();
      last = DateTime(now.year, now.month, now.day - 40);
      for (var k = 3; k >= 0; k--) {
        final start = last.subtract(Duration(days: 29 * k));
        final p = await harness.services.cycleStartPeriod(start);
        await harness.services.cycleEndPeriod(
          p.id,
          start.add(const Duration(days: 4)),
        );
      }
    });

    tearDown(() => harness.dispose());

    Future<bool> gentleOn(DateTime day) => nexCycleGentleToday(
      services: harness.services,
      preferences: harness.preferences,
      now: day,
    );

    test('is off until turned on, even on a hard day', () async {
      expect(harness.preferences.cycleGentle, isFalse);
      expect(await gentleOn(last.add(const Duration(days: 1))), isFalse);
    });

    test('the first days of a period and the days before one', () async {
      await harness.preferences.setCycleGentle(true);
      // Day 2 of the period.
      expect(await gentleOn(last.add(const Duration(days: 1))), isTrue);
      // Day 11: an ordinary day.
      expect(await gentleOn(last.add(const Duration(days: 10))), isFalse);
      // Three days before the next one.
      expect(await gentleOn(last.add(const Duration(days: 26))), isTrue);
    });

    test('what was logged wins, in every mode', () async {
      await harness.preferences.setCycleGentle(true);
      await harness.preferences.setCycleMode(CycleMode.breastfeeding);
      final day = last.add(const Duration(days: 10));
      expect(await gentleOn(day), isFalse);
      await harness.services.cycleSaveDay(
        CycleDayLog(day: CycleDate.of(day), mood: CycleMood.sensitive),
      );
      expect(await gentleOn(day), isTrue);
    });

    test('Cycle switched off turns it off too', () async {
      await harness.preferences.setCycleGentle(true);
      await harness.preferences.setCycleEnabled(false);
      expect(await gentleOn(last.add(const Duration(days: 1))), isFalse);
    });
  });

  group('a lookup already in the conversation', () {
    const notShared =
        'Cycle: not shared. The user has not allowed the assistant to '
        'read Cycle. If they want this, it is "Let the assistant read Cycle" '
        "in Cycle's settings.";
    const shared =
        'Cycle (menstrual cycle data the user chose to share; answer kindly '
        'and never as a diagnosis):\nMode: regular\nCycle day 11';

    test('says what is true now once sharing is turned on', () {
      final out = nexCycleFindingsAsOfNow(
        '<<<NOTES\n$notShared\nNOTES>>>',
        shared,
      );
      expect(out, '<<<NOTES\n$shared\nNOTES>>>');
    });

    test('stops carrying the summary once sharing is turned off', () {
      final out = nexCycleFindingsAsOfNow(
        '<<<NOTES\n$shared\nNOTES>>>',
        notShared,
      );
      expect(out, '<<<NOTES\n$notShared\nNOTES>>>');
      expect(out, isNot(contains('Cycle day')));
    });

    test('leaves the other lookups in the same turn alone', () {
      const search = 'Results for "dentist":\n[n1] dentist on Monday';
      final out = nexCycleFindingsAsOfNow(
        '<<<NOTES\n$shared\nThreads:\n- Trip (3 notes)\n$search\nNOTES>>>',
        notShared,
      );
      expect(
        out,
        '<<<NOTES\n$notShared\nThreads:\n- Trip (3 notes)\n$search\nNOTES>>>',
      );
    });

    test('a turn with no Cycle part comes back as it was', () {
      const turn = '<<<NOTES\nThreads:\n(none)\nNOTES>>>';
      expect(nexCycleFindingsAsOfNow(turn, shared), turn);
    });
  });
}
