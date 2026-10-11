import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_core/nex_core.dart';

/// Reported: the assistant treated ticked checklist items as still to do.
/// What it reads says which is which in words, not in `- [x]` marks.
void main() {
  Note checklist(String body) {
    final now = DateTime.utc(2026, 10, 9);
    return Note(
      id: 'c',
      type: NoteType.checklist,
      content: body,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  test('done and open items are named as such', () {
    final line = checklistContextLine(
      checklist('- [x] Buy milk\n- [ ] Call Sara\n- [x] Pay rent'),
    );
    expect(
      line,
      'still to do: #1 Call Sara. already done: #0 Buy milk; #2 Pay rent',
    );
  });

  test('a list with everything done says nothing is left', () {
    final line = checklistContextLine(checklist('- [x] One\n- [x] Two'));
    expect(line, 'already done: #0 One; #1 Two');
    expect(line, isNot(contains('still to do')));
  });

  group('reminders', () {
    final now = DateTime.utc(2026, 10, 9, 12);
    Note reminded(DateTime? due, [NoteRepeat repeat = NoteRepeat.once]) => Note(
      id: 'r',
      type: NoteType.text,
      content: 'Passport',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
      dueAt: due,
      dueRepeat: repeat,
    );

    // Reported: the assistant offered a reminder for a note that had one.
    test('a reminder to come is said, in the shape remind takes', () {
      final due = DateTime(2026, 10, 16, 9);
      expect(
        reminderContextLabel(reminded(due.toUtc()), now),
        'reminder set: 2026-10-16T09:00',
      );
    });

    test('a repeating one says so, even past its first time', () {
      final due = DateTime(2026, 10, 1, 8, 30);
      expect(
        reminderContextLabel(reminded(due.toUtc(), NoteRepeat.weekly), now),
        'reminder set: 2026-10-01T08:30, repeats weekly',
      );
    });

    test('none, or a one-off already gone off, says nothing', () {
      expect(reminderContextLabel(reminded(null), now), isNull);
      expect(
        reminderContextLabel(reminded(DateTime.utc(2026, 10, 1)), now),
        isNull,
      );
    });
  });

  // "Pin it" for a pinned note, "what did I write last week" with no dates,
  // `check` by an index the list no longer showed.
  group('what a note line says about it', () {
    final now = DateTime.utc(2026, 10, 9, 12);
    Note note({DateTime? pinnedAt, DateTime? dueAt}) => Note(
      id: 'n',
      type: NoteType.text,
      content: 'Boiler',
      createdAt: DateTime(2026, 10, 3, 10),
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
      pinnedAt: pinnedAt,
      dueAt: dueAt,
    );

    test('pinned, the reminder and the day it was written', () {
      expect(
        noteContextMarks(
          note(pinnedAt: now, dueAt: DateTime(2026, 10, 20, 9).toUtc()),
          now,
        ),
        'pinned; reminder set: 2026-10-20T09:00; written 2026-10-03',
      );
    });

    test('an ordinary note says only when it was written', () {
      expect(noteContextMarks(note(), now), 'written 2026-10-03');
    });

    test('a recurring item names its cadence and next date', () {
      final at = DateTime(2026, 10, 12, 8);
      NexCommitment item(
        int every,
        NexCadence cadence, {
        bool paused = false,
      }) => NexCommitment(
        id: 'c',
        title: 'Tablet',
        cadence: cadence,
        every: every,
        dueAt: at,
        createdAt: at,
        updatedAt: at,
        paused: paused,
      );
      expect(
        commitmentContextLine(item(8, NexCadence.hours)),
        '- Tablet: every 8 hours, next due 2026-10-12T08:00',
      );
      expect(
        commitmentContextLine(item(1, NexCadence.years, paused: true)),
        '- Tablet: every year, next due 2026-10-12T08:00, paused',
      );
    });
  });
}
