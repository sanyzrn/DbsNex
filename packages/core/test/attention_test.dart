import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// One reading of the library, tested as arithmetic.
///
/// The mandatory case from the 2.9.0 brief lives here first: at 10:30 a note
/// due at 11:20 and one at 11:46 are *upcoming*, and nothing about them is
/// said in the past tense. The brief and the notification are separate
/// surfaces with separate wording, but they share this reading — so a status
/// that is wrong here is wrong in both of them.
void main() {
  final at = DateTime(2026, 3, 10, 10, 30);

  Note note({
    required String id,
    required String text,
    DateTime? dueAt,
    DateTime? updatedAt,
    bool urgent = false,
    bool deleted = false,
    DateTime? aside,
    NoteType type = NoteType.text,
  }) => Note(
    id: id,
    type: type,
    content: text,
    isUrgent: urgent,
    dueAt: dueAt,
    createdAt: (updatedAt ?? at).subtract(const Duration(days: 2)),
    updatedAt: updatedAt ?? at,
    deletedAt: deleted ? at : null,
    setAsideAt: aside,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  NexCommitment commitment({
    required String id,
    required DateTime dueAt,
    NexCadence cadence = NexCadence.weeks,
    int every = 1,
    Map<String, dynamic> details = const {},
    bool paused = false,
  }) => NexCommitment(
    id: id,
    title: id,
    cadence: cadence,
    every: every,
    dueAt: dueAt,
    paused: paused,
    createdAt: at,
    updatedAt: at,
    details: details,
  );

  test('a reminder later today is upcoming, not overdue and not done', () {
    final attention = nexAttention([
      note(
        id: 'first',
        text: 'call the bank',
        dueAt: DateTime(2026, 3, 10, 11, 20),
      ),
      note(
        id: 'second',
        text: 'send the file',
        dueAt: DateTime(2026, 3, 10, 11, 46),
      ),
    ], now: at);
    expect(attention.overdue, isEmpty);
    expect(attention.today.map((i) => i.title), [
      'call the bank',
      'send the file',
    ]);
    for (final item in attention.today) {
      expect(item.state, 'due-today');
      expect(item.isWaiting, isTrue);
    }
    // And after their moment has passed they are overdue — the only change is
    // the clock, nothing was answered in between.
    final later = nexAttention([
      note(
        id: 'first',
        text: 'call the bank',
        dueAt: DateTime(2026, 3, 10, 11, 20),
      ),
    ], now: DateTime(2026, 3, 10, 12));
    expect(later.overdue.single.state, 'overdue');
  });

  test('ticking off early is a flag, not a status', () {
    // A weekly item six hours out is inside its day-before window: it may be
    // ticked off, and it is still due today. The two are different questions
    // and the model is told both.
    final open = nexAttention(
      const [],
      commitments: [
        commitment(id: 'bins', dueAt: at.add(const Duration(hours: 6))),
      ],
      now: at,
    ).items.single;
    expect(open.kind, NexAttentionKind.today);
    expect(open.canCompleteEarly, isTrue);
    expect(open.opensAt, isNull);

    // A monthly item three days out with the window not yet open: due soon,
    // cannot be ticked, and the ledger can say when it could be.
    final shut = nexAttention(
      const [],
      commitments: [
        commitment(
          id: 'rent',
          cadence: NexCadence.months,
          dueAt: at.add(const Duration(days: 4)),
        ),
      ],
      now: at,
    ).items.single;
    expect(shut.kind, NexAttentionKind.soon);
    expect(shut.canCompleteEarly, isFalse);
    expect(shut.opensAt, isNotNull);
    expect(shut.opensAt!.isAfter(at), isTrue);
  });

  test('an old overdue item still outranks a distant future one', () {
    final attention = nexAttention([
      note(
        id: 'old',
        text: 'renew the passport',
        dueAt: at.subtract(const Duration(days: 30)),
      ),
      note(
        id: 'future',
        text: 'renew the insurance',
        dueAt: at.add(const Duration(days: 5)),
      ),
    ], now: at);
    expect(attention.items.first.title, 'renew the passport');
    expect(attention.items.last.title, 'renew the insurance');
  });

  test('urgent is kept beside the status, not instead of it', () {
    // The brief counts an urgent overdue note as overdue; the nudge gives it
    // its own first line. One note, two surfaces, and the boolean is what
    // lets both be right.
    final item = nexAttention([
      note(
        id: 'fire',
        text: 'the alarm code',
        urgent: true,
        dueAt: at.subtract(const Duration(hours: 2)),
      ),
    ], now: at).items.single;
    expect(item.kind, NexAttentionKind.overdue);
    expect(item.urgent, isTrue);
  });

  test('similar notes are grouped and never merged', () {
    final attention = nexAttention([
      note(id: 'a', text: 'Trip to Tabriz tickets'),
      note(id: 'b', text: 'Trip hotel in Tabriz'),
      note(id: 'c', text: 'buy milk'),
    ], now: at);
    final trip = attention.clusters.firstWhere(
      (cluster) => cluster.label.contains('tabriz') || cluster.label == 'trip',
    );
    expect(trip.items.map((item) => item.noteId), containsAll(['a', 'b']));
    expect(trip.items, hasLength(2));
    // The independent note keeps its own identity and its own cluster.
    final milk = attention.byId('note:c')!;
    expect(milk.cluster, 'note:c');
  });

  test('a note with nothing due is an idea only while it is recent', () {
    final fresh = nexAttention([
      note(
        id: 'idea',
        text: 'the kitchen could be rearranged around the window',
      ),
    ], now: at).ideas;
    expect(fresh.single.kind, NexAttentionKind.idea);
    expect(fresh.single.score, greaterThan(0));

    final old = nexAttention([
      note(
        id: 'old',
        text: 'the kitchen could be rearranged around the window',
        updatedAt: at.subtract(const Duration(days: 30)),
      ),
    ], now: at).ideas;
    expect(old.single.score, 0, reason: 'in the library, not news');

    final without = nexAttention(
      [
        note(
          id: 'idea',
          text: 'the kitchen could be rearranged around the window',
        ),
      ],
      now: at,
      includeIdeas: false,
    );
    expect(without.ideas, isEmpty);
  });

  test('deleted and set-aside notes are not waiting on anybody', () {
    final attention = nexAttention([
      note(
        id: 'gone',
        text: 'cancelled',
        dueAt: at.subtract(const Duration(days: 1)),
        deleted: true,
      ),
      note(
        id: 'aside',
        text: 'later',
        dueAt: at.subtract(const Duration(days: 1)),
        aside: at.subtract(const Duration(days: 1)),
      ),
    ], now: at);
    expect(attention.waiting, isEmpty);
    // The count the brief reports is of the library, not of what is waiting:
    // the set-aside note is still there to be read.
    expect(attention.liveNotes, 1);
  });

  test('the ledger states the computed status for the model to respect', () {
    final ledger = nexAttentionLedger(
      nexAttention([
        note(
          id: 'first',
          text: 'call the bank',
          dueAt: DateTime(2026, 3, 10, 11, 20),
        ),
        note(
          id: 'late',
          text: 'pay the rent',
          dueAt: at.subtract(const Duration(days: 2)),
        ),
      ], now: at),
    );
    expect(ledger, contains('FACTS COMPUTED BY THE APP'));
    expect(ledger, contains('1 overdue'));
    expect(ledger, contains('DUE-TODAY'));
    expect(ledger, contains('OVERDUE'));
    expect(ledger, contains('call the bank'));
    expect(ledger, contains('11:20'));
  });

  group('a generated brief is checked against the facts', () {
    final waiting = nexAttention([
      note(
        id: 'first',
        text: 'call the bank',
        dueAt: DateTime(2026, 3, 10, 11, 20),
      ),
    ], now: at);
    final overdue = nexAttention([
      note(
        id: 'late',
        text: 'pay the rent',
        dueAt: at.subtract(const Duration(days: 2)),
      ),
    ], now: at);

    test('a false claim about overdue items is rejected', () {
      expect(
        nexAttentionContradicts('Nothing overdue today.', overdue),
        isTrue,
      );
      expect(
        nexAttentionContradicts('چیزی عقب نیفتاده، روز آرامی است.', overdue),
        isTrue,
      );
    });

    test('a false all-clear is rejected', () {
      expect(
        nexAttentionContradicts('All done — nothing is due today.', waiting),
        isTrue,
      );
      expect(
        nexAttentionContradicts(
          'همه انجام شده و چیزی برای انجام نمانده.',
          waiting,
        ),
        isTrue,
      );
    });

    test('an honest line is not', () {
      expect(
        nexAttentionContradicts('Call the bank at 11:20.', waiting),
        isFalse,
      );
      expect(
        nexAttentionContradicts('Nothing overdue today.', waiting),
        isFalse,
        reason: 'there really is nothing overdue in this library',
      );
      expect(nexAttentionContradicts('', waiting), isFalse);
    });
  });
}
