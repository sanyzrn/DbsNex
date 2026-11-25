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
    List<Tag> tags = const [],
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
    tags: tags,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  Tag tag(String name) => Tag(id: name, name: name, createdAt: at);

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

  group('two records about one subject are found, not guessed', () {
    test('a shared tag groups titles that share no word', () {
      final attention = nexAttention([
        note(id: 'a', text: 'flight booking', tags: [tag('Tabriz trip')]),
        note(id: 'b', text: 'hotel deposit', tags: [tag('Tabriz trip')]),
        note(id: 'c', text: 'buy milk'),
      ], now: at);
      final group = attention.clusters.single;
      expect(group.items.map((item) => item.id), ['note:a', 'note:b']);
      expect(group.label, 'tabriz trip');
      expect(attention.byId('note:c')!.cluster, 'note:c');
    });

    test('the same word typed two ways is one word', () {
      // The two letter forms Persian keyboards produce, and the plural beside
      // the singular: «قبضهاي» and «قبض» are one subject, «قبض».
      final attention = nexAttention([
        note(id: 'a', text: 'قبضهاي برق'),
        note(id: 'b', text: 'قبض برق'),
      ], now: at);
      expect(attention.clusters, hasLength(1));
      expect(attention.clusters.single.items, hasLength(2));
      expect(nexAttentionStem('قبضهاي'), nexAttentionStem('قبض'));
      expect(nexAttentionStem('invoices'), nexAttentionStem('invoice'));
    });

    test('a word every third note carries groups nothing', () {
      final note1 = note(
        id: 'a',
        text: 'shopping for the trip',
        tags: const [],
      );
      final attention = nexAttention([
        note1,
        note(id: 'b', text: 'shopping for the office'),
        note(id: 'c', text: 'shopping for the school'),
        note(id: 'd', text: 'shopping for the car'),
      ], now: at);
      // "shopping" appears in every title, which says nothing about these four
      // being one subject; "trip", "office", "school" and "car" do, and
      // each belongs to one note.
      expect(attention.clusters, isEmpty);
    });
  });

  group('the moment the facts change is known in advance', () {
    test('the next boundary is the next due time', () {
      final attention = nexAttention([
        note(id: 'a', text: 'call', dueAt: DateTime(2026, 3, 10, 11, 20)),
        note(id: 'b', text: 'send', dueAt: DateTime(2026, 3, 10, 11, 46)),
      ], now: at);
      expect(
        nexAttentionNextBoundary(attention),
        DateTime(2026, 3, 10, 11, 20),
      );
    });

    test('a day with nothing left falls back to midnight', () {
      final attention = nexAttention([
        note(id: 'a', text: 'an idea worth keeping'),
      ], now: at);
      expect(nexAttentionNextBoundary(attention), DateTime(2026, 3, 11));
    });

    test('an early window opening is a boundary too', () {
      final attention = nexAttention(
        const [],
        commitments: [
          commitment(
            id: 'dose',
            cadence: NexCadence.days,
            dueAt: DateTime(2026, 3, 10, 22),
            details: {'earlyWindowMinutes': 60},
          ),
        ],
        now: at,
      );
      // The moment the tick becomes available is the next thing that changes,
      // and it comes before the new day.
      expect(nexAttentionNextBoundary(attention), DateTime(2026, 3, 10, 21));
    });

    test('nothing after now means no boundary but the new day', () {
      expect(
        nexAttentionNextBoundary(nexAttention(const [], now: at)),
        DateTime(2026, 3, 11),
      );
    });
  });

  group('a brief is held to the ledger, not to a word list', () {
    final attention = nexAttention([
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
    ], now: at);

    test('a future time is not called past', () {
      final violations = nexAttentionViolations(
        'The 11:20 call was missed.',
        attention,
      );
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('still ahead'));
    });

    test('a line that also names what really slipped is left alone', () {
      expect(
        nexAttentionViolations(
          'Pay the rent: it is overdue. Call the bank at 11:20.',
          attention,
        ),
        isEmpty,
      );
    });

    test('a count the app did not compute is refused', () {
      expect(
        nexAttentionContradicts('3 overdue and 1 due today.', attention),
        isTrue,
      );
      expect(
        nexAttentionContradicts('1 overdue and 1 due today.', attention),
        isFalse,
      );
    });

    test('a negation keeps an honest line honest', () {
      expect(
        nexAttentionViolations(
          'Call the bank at 11:20 — it is not done yet.',
          attention,
        ),
        isEmpty,
      );
    });
  });

  group('the ledger is bounded but never silent about the cut', () {
    test('what did not fit is counted out loud', () {
      final many = [
        for (var i = 0; i < 60; i++)
          note(
            id: 'n$i',
            text: 'item number $i with a title long enough to fill the budget',
            dueAt: DateTime(2026, 3, 10, 12).add(Duration(minutes: i)),
          ),
      ];
      final ledger = nexAttentionLedger(
        nexAttention(many, now: at),
        budget: 900,
      );
      expect(ledger, contains('FACTS COMPUTED BY THE APP'));
      expect(ledger, contains('more waiting and not listed here'));
      expect(ledger.length, lessThan(1400));
    });

    test('items beyond the horizon are counted, not left to be guessed', () {
      final ledger = nexAttentionLedger(
        nexAttention([
          note(
            id: 'a',
            text: 'renew the passport',
            dueAt: DateTime(2026, 5, 1),
          ),
        ], now: at),
      );
      expect(ledger, contains('1 beyond it'));
    });
  });

  group('the library\'s own meaning groups what words do not', () {
    test('a semantic pair groups titles that share no word or tag', () {
      final attention = nexAttention(
        [
          note(id: 'a', text: 'the dentist'),
          note(id: 'b', text: 'tooth appointment'),
          note(id: 'c', text: 'buy milk'),
        ],
        now: at,
        semanticPairs: [(a: 'a', b: 'b')],
      );
      final group = attention.clusters.single;
      expect(
        group.items.map((item) => item.id),
        containsAll(['note:a', 'note:b']),
      );
      expect(group.items, hasLength(2));
      expect(attention.byId('note:a')!.cluster, group.label);
      expect(attention.byId('note:b')!.cluster, group.label);
      expect(attention.byId('note:c')!.cluster, 'note:c');
      // Grouping never merges: both records keep their own ids and titles.
      expect(attention.items, hasLength(3));
    });

    test('a pair naming a note outside the reading groups nothing', () {
      final attention = nexAttention(
        [note(id: 'a', text: 'the dentist')],
        now: at,
        semanticPairs: [(a: 'a', b: 'elsewhere')],
      );
      expect(attention.clusters, isEmpty);
    });

    test('the ledger carries the semantic group to the model', () {
      final attention = nexAttention(
        [
          note(
            id: 'a',
            text: 'the dentist',
            dueAt: DateTime(2026, 3, 10, 11, 20),
          ),
          note(
            id: 'b',
            text: 'tooth appointment',
            dueAt: DateTime(2026, 3, 10, 12),
          ),
        ],
        now: at,
        semanticPairs: [(a: 'a', b: 'b')],
      );
      final ledger = nexAttentionLedger(attention);
      expect(ledger, contains('RELATED: 2 items'));
    });
  });

  group('a past tense about a still-ahead item, with no clock', () {
    final attention = nexAttention([
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
    ], now: at);

    test('named in the past tense is refused', () {
      final violations = nexAttentionViolations(
        'The bank call was missed.',
        attention,
      );
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('by name'));
    });

    test('Persian is held to the same rule', () {
      final fa = nexAttention([
        note(
          id: 'bank',
          text: 'تماس با بانک',
          dueAt: DateTime(2026, 3, 10, 11, 20),
        ),
      ], now: at);
      expect(nexAttentionContradicts('تماس با بانک فراموش شد.', fa), isTrue);
      expect(
        nexAttentionContradicts('تماس با بانک هنوز انجام نشده.', fa),
        isFalse,
      );
    });

    test('an honest line about the same item is left alone', () {
      expect(
        nexAttentionViolations('Call the bank before noon.', attention),
        isEmpty,
      );
      expect(
        nexAttentionViolations(
          'Pay the rent: it is overdue. The bank call was missed.',
          attention,
        ),
        isEmpty,
        reason: 'the past tense may belong to what really slipped',
      );
    });

    test('a word every third note carries convicts nobody', () {
      final generic = nexAttention([
        for (var i = 0; i < 4; i++)
          note(
            id: 'n$i',
            text: 'shopping for the house',
            dueAt: DateTime(2026, 3, 10, 11, 20 + i),
          ),
      ], now: at);
      // "shopping" and "house" are in every title; neither is a name.
      expect(
        nexAttentionViolations('The shopping was finished.', generic),
        isEmpty,
      );
    });
  });
}
