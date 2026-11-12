import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/daily_nudge_content.dart';
import 'package:nex_core/nex_core.dart';

Note note(
  String id, {
  String? body,
  bool urgent = false,
  DateTime? due,
  NoteRepeat repeat = NoteRepeat.once,
  DateTime? acked,
  NoteType type = NoteType.text,
  DateTime? updated,
  DateTime? deleted,
  DateTime? archived,
  List<ChecklistItem>? items,
}) => Note(
  id: id,
  type: type,
  content: items == null ? body ?? id : formatChecklist(items),
  isUrgent: urgent,
  dueAt: due,
  dueRepeat: repeat,
  reminderAckedAt: acked,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: updated ?? DateTime(2026, 11, 3),
  deletedAt: deleted,
  setAsideAt: archived,
  deviceId: 'test',
  rev: 1,
  syncState: SyncState.pending,
);

void main() {
  final now = DateTime(2026, 11, 3, 8);
  for (final fa in [false, true]) {
    List<String> local(
      List<Note> notes, {
      bool hasData = true,
      List<NexCommitment> commitments = const [],
    }) => NexDailyNudgeContent.local(
      NexNudgeSnapshot(
        notes: notes,
        commitments: commitments,
        hasData: hasData,
      ),
      now,
      persian: fa,
    );

    test('$fa actual empty library gets exactly the five supplied prompts', () {
      expect(
        local([], hasData: false),
        fa ? NexDailyNudgeContent.emptyFa : NexDailyNudgeContent.emptyEn,
      );
      expect(local([], hasData: false), hasLength(5));
    });
    test(
      '$fa quiet nonempty library gets a review invitation, not onboarding',
      () {
        expect(
          local([]),
          fa ? NexDailyNudgeContent.quietFa : NexDailyNudgeContent.quietEn,
        );
        expect(
          local([]),
          isNot(
            fa ? NexDailyNudgeContent.emptyFa : NexDailyNudgeContent.emptyEn,
          ),
        );
      },
    );
    test('$fa urgent and nearby reminders have factual, compact variants', () {
      final bodies = local([
        note('urgent-plan', urgent: true),
        note('call-printshop', due: now.add(const Duration(hours: 2))),
      ]);
      for (final body in bodies) {
        expect(body, contains('urgent-plan'));
        expect(body, contains('call-printshop'));
        expect(body.runes.length, lessThanOrEqualTo(210));
      }
      expect(bodies.toSet(), hasLength(3));
    });
    test(
      '$fa stale, archived, deleted and completed tasks are not current',
      () {
        final bodies = local([
          note('ancient', due: DateTime(2020)),
          note('deleted', urgent: true, deleted: now),
          note('archived', urgent: true, archived: now),
          note(
            'done',
            urgent: true,
            type: NoteType.checklist,
            items: [const ChecklistItem(text: 'done', done: true)],
          ),
          note(
            'stale-list',
            updated: DateTime(2020),
            type: NoteType.checklist,
            items: [const ChecklistItem(text: 'old', done: false)],
          ),
        ]);
        expect(
          bodies,
          fa ? NexDailyNudgeContent.quietFa : NexDailyNudgeContent.quietEn,
        );
      },
    );
    test('$fa a plan never quotes an empty note title', () {
      // `formatChecklist` drops blank lines, so the library cannot store one
      // today. This pins the plan's own rule — the same fallback covers a
      // file note whose original name is empty — so a notification can never
      // read «» instead of naming the note it is about.
      final bodies = NexDailyNudgeContent.local(
        NexNudgeSnapshot(
          notes: [
            note('blank-list', type: NoteType.checklist, items: const []),
          ],
          commitments: const [],
          hasData: true,
        ),
        now,
        persian: fa,
        itemsById: {
          'blank-list': [const ChecklistItem(text: '   ', done: false)],
        },
      );
      for (final body in bodies) {
        expect(body, isNot(contains('«»')));
        expect(body, isNot(contains('“”')));
        expect(body, contains(fa ? 'یادداشت' : 'Note'));
      }
    });
    test('$fa recent overdue reminder and unfinished list are included', () {
      final bodies = local([
        note('late-call', due: now.subtract(const Duration(days: 1))),
        note(
          'shopping',
          type: NoteType.checklist,
          items: [const ChecklistItem(text: 'bread', done: false)],
        ),
      ]);
      expect(bodies.first, contains('late-call'));
      expect(bodies.first, contains('bread'));
    });
  }
  test('a Done answers its own day, not the reminder or its repeat', () {
    final answered = note(
      'water-plants',
      due: DateTime(2026, 11, 3, 9),
      repeat: NoteRepeat.daily,
      acked: DateTime(2026, 11, 3, 10),
    );
    final snapshot = NexNudgeSnapshot(
      notes: [answered],
      commitments: const [],
      hasData: true,
    );
    String day(DateTime at) =>
        NexDailyNudgeContent.local(snapshot, at, persian: false).join(' ');
    // The ring that was answered is not read out again on the same day...
    expect(day(DateTime(2026, 11, 3, 12)), isNot(contains('water-plants')));
    // ...but the reminder itself is untouched: a repeating one is back at
    // its own time tomorrow, and the note keeps the time it was given.
    expect(day(DateTime(2026, 11, 4, 12)), contains('water-plants'));
    expect(answered.dueAt, DateTime(2026, 11, 3, 9));
    expect(answered.dueRepeat, NoteRepeat.daily);
  });

  for (final ai in [false, true]) {
    for (final summary in [false, true]) {
      test('AI=$ai summary=$summary gates cached text without a request', () {
        expect(
          NexDailyNudgeContent.canUseSummary(
            aiEnabled: ai,
            summaryEnabled: summary,
            sourceMatches: true,
            writtenAt: now,
            deliveryAt: now.add(const Duration(minutes: 20)),
            text: 'fresh',
          ),
          ai && summary,
        );
      });
    }
  }
  for (final condition in [
    'stale',
    'changed',
    'future',
    'empty',
    'different-day',
  ]) {
    test('$condition summary falls back to local facts', () {
      final written = condition == 'stale'
          ? now.subtract(const Duration(hours: 2))
          : condition == 'future'
          ? now.add(const Duration(hours: 2))
          : condition == 'different-day'
          ? DateTime(2026, 11, 2, 23, 50)
          : now;
      final at = condition == 'different-day'
          ? DateTime(2026, 11, 3, 0, 10)
          : now;
      expect(
        NexDailyNudgeContent.canUseSummary(
          aiEnabled: true,
          summaryEnabled: true,
          sourceMatches: condition != 'changed',
          writtenAt: written,
          deliveryAt: at,
          text: condition == 'empty' ? '' : 'cached',
        ),
        isFalse,
      );
    });
  }
  test('a late delivery still has that day local text', () {
    final plan = NexDailyNudgeContent.plan(
      source: const NexNudgeSnapshot(
        notes: [],
        commitments: [],
        hasData: false,
      ),
      now: now,
      minutes: 9 * 60,
      persian: false,
      title: 'Nex',
      aiEnabled: false,
      summaryEnabled: false,
      sourceMatches: false,
      summary: null,
      summaryAt: null,
      secret: false,
    );
    final today = (plan['days'] as Map<String, Object?>)['2026-11-03'] as Map;
    final dayEnd = DateTime(2026, 11, 4).millisecondsSinceEpoch - 1;
    expect(today['localExpires'], dayEnd);
    expect(
      today['expires'],
      dayEnd,
      reason: 'local facts are true until their own day ends',
    );
  });

  test('a recap keeps its hour and never outlives its day', () {
    final written = DateTime(2026, 11, 3, 22);
    final plan = NexDailyNudgeContent.plan(
      source: const NexNudgeSnapshot(notes: [], commitments: [], hasData: true),
      now: DateTime(2026, 11, 3, 22, 45),
      minutes: 22 * 60 + 50,
      persian: false,
      title: 'Nex',
      aiEnabled: true,
      summaryEnabled: true,
      sourceMatches: true,
      summary: 'fresh',
      summaryAt: written,
      secret: false,
    );
    final today = (plan['days'] as Map<String, Object?>)['2026-11-03'] as Map;
    expect(today['ai'], isTrue);
    expect(today['expires'], DateTime(2026, 11, 3, 23).millisecondsSinceEpoch);
    expect(
      today['localExpires'],
      DateTime(2026, 11, 4).millisecondsSinceEpoch - 1,
    );
  });

  test(
    'only a fresh matching same-day slot uses AI; future days are local',
    () {
      final plan = NexDailyNudgeContent.plan(
        source: const NexNudgeSnapshot(
          notes: [],
          commitments: [],
          hasData: false,
        ),
        now: now,
        minutes: 8 * 60 + 30,
        persian: true,
        title: 'Nex',
        aiEnabled: true,
        summaryEnabled: true,
        sourceMatches: true,
        summary: '**خلاصه تازه**',
        summaryAt: now,
        secret: true,
      );
      final days = plan['days'] as Map<String, Object?>;
      final today = days['2026-11-03'] as Map;
      expect(today['ai'], isTrue);
      expect(today['bodies'], ['خلاصه تازه']);
      expect((days['2026-11-04'] as Map)['ai'], isFalse);
      expect(plan['secret'], isTrue);
      expect((today['localBodies'] as List), NexDailyNudgeContent.emptyFa);
    },
  );
}
