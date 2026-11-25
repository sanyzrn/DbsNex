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
    test('$fa a library with nothing due is left in peace, not sent a generic '
        'line (2.8.1)', () {
      expect(local([]), isEmpty);
    });
    test('$fa facts are one a line, most pressing first, with no lead-in', () {
      final bodies = local([
        note('call-printshop', due: now.add(const Duration(hours: 2))),
        note('urgent-plan', urgent: true),
      ]);
      expect(bodies, hasLength(1));
      final lines = bodies.single.split('\n');
      expect(lines, hasLength(2));
      expect(
        lines.first,
        fa
            ? 'فوری: «\u2068urgent-plan\u2069»'
            : 'Urgent: “\u2068urgent-plan\u2069”',
      );
      expect(
        lines.last,
        fa
            ? 'امروز ساعت ۱۰:۰۰ · «\u2068call-printshop\u2069»'
            : 'Today at 10:00 · “\u2068call-printshop\u2069”',
      );
      // The run-on frame this replaced: "A quick reminder: Urgent: …".
      expect(bodies.single, isNot(contains('quick reminder')));
      expect(bodies.single, isNot(contains('یادآوری کوتاه')));
    });
    test('$fa at most four facts, each one short line, the rest counted', () {
      final bodies = local([
        for (var i = 0; i < 6; i++)
          note('urgent-$i-${'x' * 120}', urgent: true),
      ]);
      final lines = bodies.single.split('\n');
      expect(lines, hasLength(5));
      for (final line in lines) {
        expect(line.runes.length, lessThanOrEqualTo(90));
      }
      expect(lines.last, fa ? '+ ۲ مورد دیگر' : '+ 2 more');
    });
    test('$fa the title counts what is waiting (2.8.1)', () {
      final source = NexNudgeSnapshot(
        notes: [
          note('call', due: now.add(const Duration(hours: 2))),
          note('late', due: now.subtract(const Duration(days: 1))),
          note('fire', urgent: true),
        ],
        commitments: const [],
        hasData: true,
      );
      expect(
        NexDailyNudgeContent.headline(source, now, persian: fa),
        fa
            ? '۱ فوری · ۱ عقب‌افتاده · ۱ برای امروز'
            : '1 urgent · 1 overdue · 1 today',
      );
      expect(
        NexDailyNudgeContent.headline(
          const NexNudgeSnapshot(notes: [], commitments: [], hasData: true),
          now,
          persian: fa,
        ),
        isNull,
      );
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
        expect(bodies, isEmpty);
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
  // The nudge has its own policy — four lines, two days, the next occurrence
  // of a repeating reminder — but it must never disagree with the brief about
  // what a status means. This is the mandatory 2.9.0 morning in both.
  for (final fa in [false, true]) {
    final at = DateTime(2026, 11, 3, 10, 30);
    List<String> local(List<Note> notes) => NexDailyNudgeContent.local(
      NexNudgeSnapshot(notes: notes, commitments: const [], hasData: true),
      at,
      persian: fa,
    );

    test('$fa two reminders later today are upcoming at 10:30', () {
      final bodies = local([
        note('bank', body: 'call the bank', due: DateTime(2026, 11, 3, 11, 20)),
        note('file', body: 'send the file', due: DateTime(2026, 11, 3, 11, 46)),
      ]);
      // One notification body, two lines in it.
      expect(bodies, hasLength(1));
      final lines = bodies.single.split('\n');
      expect(lines, hasLength(2));
      final text = bodies.single;
      expect(text, isNot(contains(fa ? 'عقب‌افتاده' : 'Overdue')));
      expect(text, isNot(contains(fa ? 'انجام شده' : 'Done')));
      expect(text, contains(fa ? 'امروز ساعت' : 'Today at'));
      expect(
        lines.where((line) => line.contains(fa ? '۱۱:۲۰' : '11:20')),
        hasLength(1),
      );
      expect(
        lines.where((line) => line.contains(fa ? '۱۱:۴۶' : '11:46')),
        hasLength(1),
      );
    });

    test('$fa an idea never makes a nudge on its own', () {
      // 2.8.1's silence rule still holds: a thought with no date is not news.
      expect(
        local([
          note(
            'idea',
            body: 'the kitchen could be rearranged around the window',
            updated: DateTime(2026, 11, 2, 9),
          ),
        ]),
        isEmpty,
      );
      // On a day that already has something to say, and with room left, it
      // rides along after the fact — never in place of one.
      final bodies = local([
        note(
          'idea',
          body: 'the kitchen could be rearranged around the window',
          updated: DateTime(2026, 11, 2, 9),
        ),
        note('bank', body: 'call the bank', due: DateTime(2026, 11, 3, 11, 20)),
      ]);
      expect(bodies, hasLength(1));
      final lines = bodies.single.split('\n');
      expect(lines, hasLength(2));
      expect(lines.first, contains(fa ? 'امروز ساعت' : 'Today at'));
      expect(lines.last, contains(fa ? 'ایده' : 'Idea'));
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
    'a recap whose facts have expired is not delivered, even within the hour',
    () {
      // Written at 07:00, an item falls due at 07:20, the nudge is at 07:30:
      // the hour and the day still match, but the sentence stopped being true
      // ten minutes ago. The local facts are what the notification carries.
      final written = DateTime(2026, 11, 3, 7);
      final expired = DateTime(2026, 11, 3, 7, 20);
      expect(
        NexDailyNudgeContent.canUseSummary(
          aiEnabled: true,
          summaryEnabled: true,
          sourceMatches: true,
          writtenAt: written,
          deliveryAt: DateTime(2026, 11, 3, 7, 30),
          text: 'nothing is overdue',
          validUntil: expired,
        ),
        isFalse,
      );
      // Before the expiry the same recap is still usable.
      expect(
        NexDailyNudgeContent.canUseSummary(
          aiEnabled: true,
          summaryEnabled: true,
          sourceMatches: true,
          writtenAt: written,
          deliveryAt: DateTime(2026, 11, 3, 7, 10),
          text: 'nothing is overdue',
          validUntil: expired,
        ),
        isTrue,
      );
      final plan = NexDailyNudgeContent.plan(
        source: const NexNudgeSnapshot(
          notes: [],
          commitments: [],
          hasData: true,
        ),
        now: DateTime(2026, 11, 3, 7),
        minutes: 7 * 60 + 30,
        persian: false,
        title: 'Nex',
        aiEnabled: true,
        summaryEnabled: true,
        sourceMatches: true,
        summary: 'nothing is overdue',
        summaryAt: written,
        summaryValidUntil: expired,
        secret: false,
      );
      final today = (plan['days'] as Map<String, Object?>)['2026-11-03'] as Map;
      expect(today['ai'], isFalse);
      expect(today['bodies'], isNot(contains('nothing is overdue')));
    },
  );

  test('the expiry bounds the recap window when it comes before the hour', () {
    final written = DateTime(2026, 11, 3, 7);
    final expired = DateTime(2026, 11, 3, 7, 20);
    final plan = NexDailyNudgeContent.plan(
      source: const NexNudgeSnapshot(notes: [], commitments: [], hasData: true),
      now: DateTime(2026, 11, 3, 7),
      minutes: 7 * 60 + 10,
      persian: false,
      title: 'Nex',
      aiEnabled: true,
      summaryEnabled: true,
      sourceMatches: true,
      summary: 'fresh',
      summaryAt: written,
      summaryValidUntil: expired,
      secret: false,
    );
    final today = (plan['days'] as Map<String, Object?>)['2026-11-03'] as Map;
    expect(today['ai'], isTrue);
    expect(today['expires'], expired.millisecondsSinceEpoch);
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
