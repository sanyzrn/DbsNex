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
}
