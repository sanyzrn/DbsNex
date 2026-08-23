import 'dart:convert';

import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// One Keep note, as Takeout actually writes it.
String keep({
  String? title,
  String? text,
  List<(String, bool)>? list,
  List<String> labels = const [],
  bool trashed = false,
  int? micros,
}) => jsonEncode({
  'color': 'DEFAULT',
  'isTrashed': trashed,
  'isPinned': false,
  'isArchived': false,
  'title': title ?? '',
  'userEditedTimestampUsec': micros ?? 1700000000000000,
  if (text != null) 'textContent': text,
  if (list != null)
    'listContent': [
      for (final (item, checked) in list) {'text': item, 'isChecked': checked},
    ],
  'labels': [
    for (final name in labels) {'name': name},
  ],
});

List<int> bytes(String text) => utf8.encode(text);

void main() {
  group('Google Keep', () {
    test('a text note keeps its words, title, tags and date', () {
      final result = NoteImport.readEntries([
        (
          'Takeout/Keep/groceries.json',
          bytes(
            keep(
              title: 'Groceries',
              text: 'cooler\nplane tickets',
              labels: ['Errands', 'Travel'],
              micros: 1700000000000000,
            ),
          ),
        ),
      ]);

      expect(result.notes, hasLength(1));
      final note = result.notes.single;
      expect(note.type, NoteType.text);
      expect(note.text, 'cooler\nplane tickets');
      expect(note.title, 'Groceries');
      expect(note.tags, ['Errands', 'Travel']);
      expect(
        note.createdAt,
        DateTime.fromMicrosecondsSinceEpoch(1700000000000000, isUtc: true),
      );
    });

    test('a list becomes a checklist, ticks and all', () {
      final result = NoteImport.readEntries([
        ('k.json', bytes(keep(list: [('milk', true), ('bread', false)]))),
      ]);

      final note = result.notes.single;
      expect(note.type, NoteType.checklist);
      expect(note.items, [
        const ChecklistItem(text: 'milk', done: true),
        const ChecklistItem(text: 'bread', done: false),
      ]);
      // The body is already in the format the app stores, so a caller that
      // only knows how to write text still writes a working checklist.
      expect(note.text, '- [x] milk\n- [ ] bread');
    });

    test('a note already in Keep\'s trash is not resurrected', () {
      final result = NoteImport.readEntries([
        ('a.json', bytes(keep(text: 'deleted on purpose', trashed: true))),
        ('b.json', bytes(keep(text: 'kept'))),
      ]);

      expect(result.notes.single.text, 'kept');
      expect(result.skippedTrashed, 1);
    });

    test('a note that was only a photo is counted, not silently dropped', () {
      final result = NoteImport.readEntries([
        ('a.json', bytes(keep(text: ''))),
      ]);

      expect(result.notes, isEmpty);
      expect(result.skippedAttachments, 1);
    });

    test('a title with no body is still a note', () {
      final result = NoteImport.readEntries([
        ('a.json', bytes(keep(title: 'call the dentist'))),
      ]);

      expect(result.notes.single.text, 'call the dentist');
    });

    test('an implausible timestamp is dropped, not imported', () {
      // Seconds where Keep writes microseconds — 1970 in disguise, and one
      // note dated then re-sorts an entire library around itself.
      final result = NoteImport.readEntries([
        ('a.json', bytes(keep(text: 'x', micros: 1700000000))),
      ]);

      expect(result.notes.single.createdAt, isNull);
    });

    test('some other app\'s JSON is not mistaken for a note', () {
      final result = NoteImport.readEntries([
        ('settings.json', bytes('{"theme":"dark","fontSize":14}')),
        ('broken.json', bytes('{not json at all')),
      ]);

      expect(result.notes, isEmpty);
      expect(result.unreadable, 2);
    });
  });

  group('markdown and text', () {
    test('one file is one note, named after itself', () {
      final result = NoteImport.readEntries([
        ('export/shopping-list.md', bytes('cooler\nplane tickets')),
      ]);

      final note = result.notes.single;
      expect(note.type, NoteType.text);
      expect(note.title, 'shopping list');
    });

    test('a filename that is only a timestamp is not used as a title', () {
      final result = NoteImport.readEntries([
        ('1730000000000.txt', bytes('a thought')),
      ]);

      expect(result.notes.single.title, isNull);
    });

    test('a file of task lines comes back as a checklist', () {
      final result = NoteImport.readEntries([
        ('list.md', bytes('- [x] milk\n- [ ] bread')),
      ]);

      final note = result.notes.single;
      expect(note.type, NoteType.checklist);
      expect(note.items.first.done, isTrue);
    });

    test('prose that merely contains a bracket is not a checklist', () {
      final result = NoteImport.readEntries([
        ('note.md', bytes('- [x] milk\nand then I went home')),
      ]);

      expect(result.notes.single.type, NoteType.text);
    });

    test('an empty file is not a note', () {
      final result = NoteImport.readEntries([('empty.md', bytes('   \n\n'))]);
      expect(result.notes, isEmpty);
      expect(result.unreadable, 1);
    });
  });

  group('what an archive contains besides notes', () {
    test('Takeout\'s duplicate HTML and macOS resource forks are ignored', () {
      expect(NoteImport.looksImportable('Takeout/Keep/a.html'), isFalse);
      expect(NoteImport.looksImportable('__MACOSX/._a.json'), isFalse);
      expect(NoteImport.looksImportable('Keep/.DS_Store'), isFalse);
      expect(NoteImport.looksImportable('Takeout/Keep/'), isFalse);
      expect(NoteImport.looksImportable('Takeout/Keep/a.json'), isTrue);
    });

    test('a photo beside a note is skipped without counting as unreadable', () {
      final result = NoteImport.readEntries([
        ('Takeout/Keep/a.json', bytes(keep(text: 'a note'))),
        ('Takeout/Keep/a.jpg', const [0xFF, 0xD8, 0xFF]),
      ]);

      expect(result.notes, hasLength(1));
      expect(result.unreadable, 0);
    });

    test('notes come back oldest first, undated ones last', () {
      final result = NoteImport.readEntries([
        ('c.json', bytes(keep(text: 'newest', micros: 1700000002000000))),
        ('u.md', bytes('no date')),
        ('a.json', bytes(keep(text: 'oldest', micros: 1700000001000000))),
      ]);

      expect(result.notes.map((n) => n.text).toList(), [
        'oldest',
        'newest',
        'no date',
      ]);
    });
  });
}
