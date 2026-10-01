import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/capture_journal.dart';
import 'package:nex_client/platform/editor_drafts.dart';

/// Drafts are written at most once per pause in typing, not per keystroke
/// (PERF-03), and a picture kept for recovery is written off the UI thread
/// without outliving a clear (PERF-07).
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('nex-soon-'));
  tearDown(() => root.deleteSync(recursive: true));

  group('CaptureJournal.writeSoon', () {
    test('holds the text until flushed', () {
      final journal = CaptureJournal(root.path);
      journal.writeSoon('a', 'hello');
      expect(journal.pending(), isEmpty);
      journal.flushPending();
      expect(journal.pending().single.text, 'hello');
    });

    test('the timer flushes the last text only', () async {
      final journal = CaptureJournal(root.path);
      journal.writeSoon('a', 'h');
      journal.writeSoon('a', 'hi');
      await Future<void>.delayed(
        CaptureJournal.settle + const Duration(milliseconds: 100),
      );
      expect(journal.pending().single.text, 'hi');
    });

    test('complete drops a write still waiting', () {
      final journal = CaptureJournal(root.path);
      journal.writeSoon('a', 'hello');
      journal.complete('a');
      journal.flushPending();
      expect(journal.pending(), isEmpty);
    });
  });

  group('EditorDrafts.writeSoon', () {
    test('read sees the waiting value before it reaches disk', () {
      final drafts = EditorDrafts(root.path);
      drafts.writeSoon('k', {'text': 'x'});
      expect(drafts.read('k'), {'text': 'x'});
      expect(EditorDrafts(root.path).read('k'), isNull);
      drafts.flushPending();
      expect(EditorDrafts(root.path).read('k'), {'text': 'x'});
    });

    test('clear drops a write still waiting', () {
      final drafts = EditorDrafts(root.path);
      drafts.writeSoon('k', {'text': 'x'});
      drafts.clear('k');
      drafts.flushPending();
      expect(drafts.read('k'), isNull);
    });
  });

  group('EditorDrafts.writeImage', () {
    test('keeps the picture', () async {
      final drafts = EditorDrafts(root.path);
      await drafts.writeImage('p', Uint8List.fromList([1, 2, 3]));
      expect(drafts.readImage('p'), [1, 2, 3]);
    });

    test('a clear during the write wins', () async {
      final drafts = EditorDrafts(root.path);
      final writing = drafts.writeImage('p', Uint8List(1 << 20));
      drafts.clear('p');
      await writing;
      expect(drafts.readImage('p'), isNull);
      expect(
        root.listSync(recursive: true).whereType<File>(),
        isEmpty,
        reason: 'the staging file is removed too',
      );
    });
  });
}
