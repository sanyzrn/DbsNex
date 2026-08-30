import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:nex_client/platform/db_worker.dart';

/// The real database isolate, actually spawned.
///
/// Every other test in this suite talks to `InProcessDb`, which is the right
/// trade for testing behaviour — but it means the isolate path had no cover at
/// all, and that is where the app broke: `NexDbWorker.spawn` watches the error
/// and exit ports so a database that never opens cannot hang the launch, and
/// then the constructor listened to both a second time. A `ReceivePort` is a
/// single-subscription stream, so every launch threw `Bad state: Stream has
/// already been listened to` before the first frame. A full test suite and a
/// green pipeline said nothing, because nothing here had ever spawned one.
///
/// This is deliberately not a behaviour test. It asks the one question the
/// fake cannot: does the worker come up, answer, and go away again.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_db_worker_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('spawns, answers, and closes', () async {
    final mediaDir = p.join(tmp.path, 'media');
    Directory(mediaDir).createSync(recursive: true);

    // Before the fix this threw inside the constructor, after the isolate had
    // already reported itself ready — so the failure looked like a database
    // that would not open when the database was perfectly fine.
    final worker = await NexDbWorker.spawn(
      dbPath: p.join(tmp.path, 'nex.sqlite'),
      deviceId: 'test',
      mediaDir: mediaDir,
    );

    try {
      final note = await worker.captureText('a note from the real worker');
      expect(note, isNotNull);
      expect(note!.content, 'a note from the real worker');

      // Round-trips through the isolate, so the response port is wired too.
      expect((await worker.getById(note.id))?.content, note.content);
    } finally {
      await worker.close();
    }
  });

  test('a second worker on the same path also comes up', () async {
    // The ports are per-instance. Opening one after another is what the app
    // does on a restore, and a leaked listener would show here.
    final mediaDir = p.join(tmp.path, 'media');
    Directory(mediaDir).createSync(recursive: true);
    final dbPath = p.join(tmp.path, 'nex.sqlite');

    final first = await NexDbWorker.spawn(
      dbPath: dbPath,
      deviceId: 'test',
      mediaDir: mediaDir,
    );
    await first.captureText('written by the first');
    await first.close();

    final second = await NexDbWorker.spawn(
      dbPath: dbPath,
      deviceId: 'test',
      mediaDir: mediaDir,
    );
    try {
      final notes = await second.timeline(limit: 10);
      expect(notes.map((note) => note.content), contains('written by the first'));
    } finally {
      await second.close();
    }
  });
}
