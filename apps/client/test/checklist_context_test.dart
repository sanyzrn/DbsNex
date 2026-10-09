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
}
