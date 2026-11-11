import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// `nexOneLine` is the one cap every generated surface shares — the recap's
/// per-note budget and the headline's — and the recency reserve in
/// `nexRecapSource` is counted from the notes rather than from built lines.
/// Both are small, and both are easy to break in ways only a test notices.
void main() {
  final now = DateTime.utc(2026, 7, 28, 9);

  Note note({
    required String id,
    String? content,
    NoteType type = NoteType.text,
    Duration age = Duration.zero,
    Duration? due,
  }) => Note(
    id: id,
    type: type,
    content: content,
    createdAt: now.subtract(age),
    updatedAt: now.subtract(age),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
    dueAt: due == null ? null : now.add(due),
  );

  group('nexOneLine', () {
    test('short text passes through, flattened', () {
      expect(nexOneLine('a note', 160), 'a note');
      expect(nexOneLine('  a \n note  ', 160), 'a note');
    });

    test('nothing readable in it is an empty line, not a null', () {
      expect(nexOneLine(null, 160), '');
      expect(nexOneLine('   \n\t ', 160), '');
    });

    test('long text stops at the cap, with the ellipsis after the cut', () {
      final cut = nexOneLine('a' * 300, 160);
      expect(cut.length, 161);
      expect(cut.endsWith('…'), isTrue);
    });
  });

  group('the recency reserve', () {
    List<String> linesOf(List<Note> notes, {int limit = 20}) => nexRecapSource(
      notes,
      now: now,
      limit: limit,
    ).split('\n').where((line) => line.isNotEmpty).toList();

    test('a recent note with nothing readable does not reserve a line', () {
      // The reserve exists so a busy morning still says what was just
      // written. A recent photo with no caption yet contributes no line,
      // so it must not spend the reserve either: counting it would hold a
      // line back from the reminders for a note that cannot fill it.
      final lines = linesOf([
        for (var i = 0; i < 30; i++)
          note(
            id: 'due$i',
            content: 'errand $i',
            due: Duration(hours: i + 1),
          ),
        note(id: 'blank', type: NoteType.photo),
      ]);

      expect(lines, hasLength(20));
      expect(lines.every((line) => line.startsWith('DUE')), isTrue);
    });

    test('a large library is walked only as far as the budget', () {
      // The output contract, unchanged from when every note was rendered:
      // at most [limit] lines, the pressing ones first, the ordinary ones
      // newest first behind them. Three hundred notes behind twenty lines
      // is the shape that made the old walk expensive.
      final lines = linesOf([
        note(
          id: 'due',
          content: 'the appointment',
          age: const Duration(days: 3),
          due: const Duration(hours: 6),
        ),
        for (var i = 0; i < 300; i++)
          note(
            id: 'rest$i',
            content: 'thought $i',
            age: Duration(hours: i),
          ),
      ]);

      expect(lines, hasLength(20));
      expect(lines.first, contains('the appointment'));
      expect(lines[1], contains('thought 0'));
      expect(lines.last, contains('thought 18'));
    });
  });
}
