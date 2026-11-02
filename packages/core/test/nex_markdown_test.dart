import 'dart:convert';
import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  test('legacy Nex metadata is recognised without exposing UUID as title', () {
    final read = NoteImport.readEntries([
      (
        'markdown/0190a1b2-c3d4-7000-8000-000000000001.md',
        utf8.encode('''---
id: 0190a1b2-c3d4-7000-8000-000000000001
type: text
created_at: 2024-03-20T10:30:00Z
tags: [Work, کار]
---

my own words
'''),
      ),
    ]);
    final note = read.notes.single;
    expect(note.text, 'my own words');
    expect(note.title, isNull);
    expect(note.tags, ['Work', 'کار']);
    expect(note.createdAt, DateTime.utc(2024, 3, 20, 10, 30));
  });
  for (final content in [
    '---\ntitle: Ordinary YAML\n---\nOriginal text',
    '---\nid: third-party-id\ntype: text\ncreated_at: 2024-01-01\ntags: []\n---\nOriginal text',
    '---\nid: x\ntype: text\ncreated_at: invalid\ntags: []\n---\nOriginal text',
    '---\nid: x\ntype: text\ncreated_at: 2024-01-01\ntags: broken\n---\nOriginal text',
  ]) {
    test(
      'foreign or malformed metadata stays in the note: ${content.length}',
      () {
        final note = NoteImport.readEntries([
          ('Personal.md', utf8.encode(content)),
        ]).notes.single;
        expect(note.text, content);
        expect(note.title, 'Personal');
      },
    );
  }
}
