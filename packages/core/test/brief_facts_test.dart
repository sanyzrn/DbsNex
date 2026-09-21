import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// The half of the daily brief that is arithmetic.
///
/// Worth testing on its own precisely because it is the half nobody can check
/// by reading the card: a model's line is judged by eye every morning, and a
/// wrong date is not. These are the facts every brief style is built from,
/// and under the plain report they are the entire brief.
void main() {
  final now = DateTime.utc(2026, 3, 10, 9);

  Note note({
    required String id,
    required String text,
    DateTime? dueAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    NoteType type = NoteType.text,
  }) => Note(
    id: id,
    type: type,
    content: text,
    createdAt: now.subtract(const Duration(days: 30)),
    updatedAt: updatedAt ?? now,
    deletedAt: deletedAt,
    dueAt: dueAt,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  NexCommitment commitment({
    required String title,
    required DateTime dueAt,
    bool paused = false,
  }) => NexCommitment(
    id: 'c-$title',
    title: title,
    cadence: NexCadence.months,
    every: 1,
    dueAt: dueAt,
    paused: paused,
    createdAt: now,
    updatedAt: now,
  );

  test('what has slipped comes before what is coming', () {
    final facts = nexBriefFacts(
      [
        note(
          id: '1',
          text: 'call the plumber',
          dueAt: now.subtract(const Duration(days: 2)),
        ),
        note(
          id: '2',
          text: 'dentist',
          dueAt: now.add(const Duration(days: 1)),
        ),
      ],
      now: now,
    );
    expect(facts.overdue.single.title, 'call the plumber');
    expect(facts.dueSoon.single.title, 'dentist');
    expect(facts.nothingWaiting, isFalse);
    expect(facts.waiting, 2);
  });

  test('the most overdue is first, not the most recent', () {
    final facts = nexBriefFacts(
      [
        note(
          id: '1',
          text: 'yesterday',
          dueAt: now.subtract(const Duration(days: 1)),
        ),
        note(
          id: '2',
          text: 'last month',
          dueAt: now.subtract(const Duration(days: 30)),
        ),
      ],
      now: now,
    );
    // What has been ignored longest is the thing worth saying first. Sorting
    // these by date the other way round buries a bill nobody has paid under
    // one that slipped this morning.
    expect(
      [for (final entry in facts.overdue) entry.title],
      ['last month', 'yesterday'],
    );
  });

  test('a date beyond the horizon is not waiting on anybody', () {
    final facts = nexBriefFacts(
      [
        note(
          id: '1',
          text: 'passport renewal',
          dueAt: now.add(const Duration(days: 90)),
        ),
      ],
      now: now,
    );
    // It is a note with a date on it, not something this morning needs to
    // hear about — the same horizon `nexRecapSource` uses, so a brief with a
    // model in it and one without cannot disagree about the same Tuesday.
    expect(facts.nothingWaiting, isTrue);
    expect(facts.notes, 1);
  });

  test('a deleted note is not waiting either', () {
    final facts = nexBriefFacts(
      [
        note(
          id: '1',
          text: 'cancelled',
          dueAt: now.subtract(const Duration(days: 1)),
          deletedAt: now,
        ),
      ],
      now: now,
    );
    expect(facts.nothingWaiting, isTrue);
    expect(facts.notes, 0);
  });

  test('a checklist counts once, and only while something is unticked', () {
    final open = note(
      id: '1',
      text: '- [ ] milk\n- [x] bread',
      type: NoteType.checklist,
    );
    final done = note(
      id: '2',
      text: '- [x] milk\n- [x] bread',
      type: NoteType.checklist,
    );
    final facts = nexBriefFacts([open, done], now: now);
    expect(facts.unfinished, hasLength(1));
    expect(facts.unfinished.single.remaining, 1);
    expect(facts.unfinished.single.total, 2);
  });

  test('an overdue checklist is said once, as overdue', () {
    final facts = nexBriefFacts(
      [
        note(
          id: '1',
          text: '- [ ] milk',
          type: NoteType.checklist,
          dueAt: now.subtract(const Duration(days: 1)),
        ),
      ],
      now: now,
    );
    // Both are true of it. Saying both spends two of a four-line brief on one
    // item, and the second line adds nothing the first did not.
    expect(facts.overdue, hasLength(1));
    expect(facts.unfinished, isEmpty);
  });

  test('a commitment is waiting on its own lead time, and a paused one never',
      () {
    final facts = nexBriefFacts(
      const [],
      commitments: [
        commitment(title: 'rent', dueAt: now.subtract(const Duration(days: 3))),
        commitment(
          title: 'gym',
          dueAt: now.subtract(const Duration(days: 3)),
          paused: true,
        ),
      ],
      now: now,
    );
    expect(facts.overdue.single.title, 'rent');
    expect(facts.overdue.single.recurring, isTrue);
  });

  test('a quiet library is a quiet brief', () {
    final facts = nexBriefFacts(
      [note(id: '1', text: 'a thought'), note(id: '2', text: 'another')],
      now: now,
    );
    // Not an empty one — there are two notes. Nothing is *waiting*, which is
    // an answer rather than a failure, and the thing a brief is allowed to
    // say nothing about.
    expect(facts.notes, 2);
    expect(facts.nothingWaiting, isTrue);
  });
}
