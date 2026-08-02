import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/widget_snapshot.dart';
import 'package:nex_core/nex_core.dart';

Note _note(
  String id, {
  String? content,
  String? caption,
  String? transcript,
  NoteType type = NoteType.text,
  bool pinned = false,
}) =>
    Note(
      id: id,
      type: type,
      content: content,
      caption: caption,
      transcriptText: transcript,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
      pinnedAt: pinned ? DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000) : null,
    );

void main() {
  late Directory tmp;
  late String path;
  late List<String> calls;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_widget_snap_');
    path = '${tmp.path}/widget_snapshot.json';
    calls = [];
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  WidgetSnapshotStore store({Duration interval = const Duration(milliseconds: 50)}) =>
      WidgetSnapshotStore(
        filePath: path,
        minInterval: interval,
        onPublished: () => calls.add('published'),
      );

  test('publishes a versioned snapshot of the newest notes', () async {
    await store().publish([
      _note('a', content: 'first'),
      _note('b', content: 'second', pinned: true),
    ]);

    final root = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    expect(root['v'], 1);
    expect(root['updatedAt'], isA<int>());
    final notes = root['notes'] as List<dynamic>;
    expect(notes, hasLength(2));
    expect(notes[0]['id'], 'a');
    expect(notes[0]['type'], 'text');
    expect(notes[0]['text'], 'first');
    expect(notes[0]['pinned'], false);
    expect(notes[1]['pinned'], true);
  });

  test('uses the same preview fallback chain the timeline cards use', () async {
    await store().publish([
      _note('v', caption: 'the caption'),
      _note('p', transcript: 'the transcript'),
      _note('f', content: 'the content'),
    ]);

    final notes =
        (jsonDecode(File(path).readAsStringSync())
            as Map<String, dynamic>)['notes'] as List<dynamic>;
    expect(notes[0]['text'], 'the caption');
    expect(notes[1]['text'], 'the transcript');
    expect(notes[2]['text'], 'the content');
  });

  test('caps the preview at one widget row', () async {
    await store().publish([_note('long', content: 'x' * 200)]);
    final notes =
        (jsonDecode(File(path).readAsStringSync())
            as Map<String, dynamic>)['notes'] as List<dynamic>;
    final text = notes[0]['text'] as String;
    expect(text.length, WidgetSnapshotStore.maxPreviewLength + 1);
    expect(text.endsWith('…'), isTrue);
  });

  test('keeps at most the documented number of notes', () async {
    final many = [
      for (var i = 0; i < 30; i++) _note('n$i', content: 'note $i'),
    ];
    await store().publish(many);
    final notes =
        (jsonDecode(File(path).readAsStringSync())
            as Map<String, dynamic>)['notes'] as List<dynamic>;
    expect(notes, hasLength(WidgetSnapshotStore.maxNotes));
  });

  test('a write inside the throttle window lands as a trailing write', () async {
    final s = store(interval: const Duration(milliseconds: 120));
    await s.publish([_note('a', content: 'first')]);
    // Inside the window: no immediate write, one scheduled.
    await s.publish([_note('b', content: 'second')]);
    final afterFirstPair = File(path).readAsStringSync();
    expect(afterFirstPair, contains('first'));

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final settled = File(path).readAsStringSync();
    expect(settled, contains('second'));
    expect(settled, isNot(contains('first')));
    expect(calls.length, 2, reason: 'one publish callback per actual write');
  });

  test('a failed write never throws into the capture path', () async {
    // A file sitting where a directory would have to be created makes the
    // write fail; the store swallows it and the caller's future completes.
    final blocker = File('${tmp.path}/blocker')..writeAsStringSync('x');
    final broken = WidgetSnapshotStore(
      filePath: '${blocker.path}/widget_snapshot.json',
      minInterval: const Duration(milliseconds: 20),
      onPublished: () => calls.add('published'),
    );
    await broken.publish([_note('a', content: 'x')]);
    expect(calls, isEmpty, reason: 'nothing was written, so nothing was announced');
  });
}
