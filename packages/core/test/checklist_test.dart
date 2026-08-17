import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// A checklist keeps its items in the note's own `content`, as markdown task
/// lines, rather than in a table of its own — see `models/checklist.dart` for
/// why. That makes this parser the whole feature's load-bearing part: search,
/// sync, export and merge all see a checklist as the text it is underneath.
void main() {
  test('reads ticked and unticked lines', () {
    final items = parseChecklist('- [x] milk\n- [ ] bread');

    expect(items, [
      const ChecklistItem(text: 'milk', done: true),
      const ChecklistItem(text: 'bread', done: false),
    ]);
  });

  test('accepts the shapes people actually type', () {
    // No bullet, an asterisk instead of a dash, a capital X, and ragged
    // leading space — all the same list.
    final items = parseChecklist('[x] one\n* [X] two\n   - [ ] three');

    expect(items.map((i) => i.text), ['one', 'two', 'three']);
    expect(items.map((i) => i.done), [true, true, false]);
  });

  test('a plain line is kept as an unticked item, not dropped', () {
    // Text arriving from a paste, another editor, or a text note being turned
    // into a checklist should never silently lose lines.
    final items = parseChecklist('milk\n- [x] bread');

    expect(items, [
      const ChecklistItem(text: 'milk', done: false),
      const ChecklistItem(text: 'bread', done: true),
    ]);
  });

  test('blank lines are not items', () {
    expect(parseChecklist('- [ ] a\n\n\n- [ ] b'), hasLength(2));
    expect(parseChecklist('   \n\n'), isEmpty);
    expect(parseChecklist(null), isEmpty);
  });

  test('an item with no text at all is dropped on the way out', () {
    // Clearing a line's text is how a line is deleted — there is no separate
    // remove gesture to find.
    final out = formatChecklist(const [
      ChecklistItem(text: 'kept', done: false),
      ChecklistItem(text: '   ', done: false),
      ChecklistItem(text: 'also kept', done: true),
    ]);

    expect(out, '- [ ] kept\n- [x] also kept');
  });

  test('format and parse round-trip', () {
    const items = [
      ChecklistItem(text: 'milk', done: true),
      ChecklistItem(text: 'شیر', done: false),
      ChecklistItem(text: 'bread [not a marker]', done: false),
    ];

    expect(parseChecklist(formatChecklist(items)), items);
  });

  test('progress counts ticked against total', () {
    final items = parseChecklist('- [x] a\n- [ ] b\n- [x] c');
    final progress = checklistProgress(items);

    expect(progress.done, 2);
    expect(progress.total, 3);
  });

  test('a checklist note exposes its items and searches by their text', () {
    final now = DateTime.utc(2026, 8, 17);
    final note = Note(
      id: 'c1',
      type: NoteType.checklist,
      content: '- [x] milk\n- [ ] bread',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );

    expect(note.checklistItems, hasLength(2));
    // The markers are stripped: nobody searches for "[x]".
    expect(note.searchableDerivedText, 'milk bread');
    expect(note.displayText, 'milk · bread');
  });

  test('only a checklist parses its content as one', () {
    final now = DateTime.utc(2026, 8, 17);
    final text = Note(
      id: 't1',
      type: NoteType.text,
      content: '- [x] this is just prose about a list',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );

    expect(text.checklistItems, isEmpty);
    expect(text.displayText, '- [x] this is just prose about a list');
  });

  test('a title outranks the body on any type', () {
    final now = DateTime.utc(2026, 8, 17);
    final note = Note(
      id: 'n1',
      type: NoteType.text,
      title: 'Rent',
      content: 'call the landlord back about the leak',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );

    expect(note.displayText, 'Rent');
    // Searchable by both — naming a note must not hide what is in it.
    expect(
      note.searchableDerivedText,
      'Rent call the landlord back about the leak',
    );
    // Whitespace is not a title.
    expect(note.copyWith(title: '   ').displayText, isNot('   '));
  });

  test('a link note keeps the URL as its content', () {
    final now = DateTime.utc(2026, 8, 17);
    final note = Note(
      id: 'l1',
      type: NoteType.link,
      content: '  https://example.com/a  ',
      linkExcerpt: 'An example page',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );

    expect(note.linkUrl, 'https://example.com/a');
    // The excerpt is what a card reads out, but the URL stays searchable —
    // going back to a bookmark by its domain is the obvious way to find one.
    expect(note.displayText, 'An example page');
    expect(note.searchableDerivedText, contains('example.com'));
    // Every other type answers null, so callers need no type check.
    expect(note.copyWith().linkUrl, 'https://example.com/a');
  });
}
