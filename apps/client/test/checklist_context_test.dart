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
    expect(line, 'still to do: Call Sara. already done: Buy milk; Pay rent');
  });

  test('a list with everything done says nothing is left', () {
    final line = checklistContextLine(checklist('- [x] One\n- [x] Two'));
    expect(line, 'already done: One; Two');
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
}
