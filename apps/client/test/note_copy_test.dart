import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/note_copy.dart';
import 'package:nex_core/nex_core.dart';

/// Copy on a file note copies the file's words, not its name, unless the
/// note has a caption.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('nex-copy-'));
  tearDown(() => root.deleteSync(recursive: true));

  Note file(String path, {String? caption}) => Note(
    id: 'n1',
    type: NoteType.file,
    content: 'notes.md',
    mediaUri: path,
    caption: caption,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  test('a Markdown file copies its text', () async {
    final path = '${root.path}/notes.md';
    File(path).writeAsStringSync('# Title\n\nBody\n');
    expect(await nexCopyTextOf(file(path)), '# Title\n\nBody');
  });

  test('a caption still wins', () async {
    final path = '${root.path}/notes.md';
    File(path).writeAsStringSync('Body');
    expect(await nexCopyTextOf(file(path, caption: 'mine')), 'mine');
  });

  test('a missing or binary file falls back to its name', () async {
    expect(await nexCopyTextOf(file('${root.path}/gone.md')), 'notes.md');
    final path = '${root.path}/photo.bin';
    File(path).writeAsBytesSync([0, 1, 2]);
    expect(await nexCopyTextOf(file(path)), 'notes.md');
  });
}
