import 'dart:io';
import 'dart:isolate';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Two connections writing the same library — the share window and the app.
///
/// Release CI failed on exactly this: one connection held the write lock
/// longer than the other's five-second busy timeout, and a shared capture
/// died on `BEGIN IMMEDIATE` with "database is locked". Waiting five real
/// seconds in a test is slow and still a race, so the waiting connection's
/// timeout is set to zero here instead: without the retry it fails at once,
/// every time.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('nex_contention_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a capture waits out a writer that outlasts the busy timeout', () async {
    final path = p.join(tmp.path, 'nex.sqlite');
    final holder = NexDatabase.open(path);
    holder.db.beginImmediate();

    final capture = Isolate.run(() {
      final db = NexDatabase.open(path);
      try {
        db.db.execute('PRAGMA busy_timeout = 0;');
        return SqliteNoteRepository(db, localDeviceId: 'share').captureShared({
          'requestId': 'r-1',
          'type': 'shared_text',
          'text': 'written while the app was busy',
        })?.content;
      } finally {
        db.close();
      }
    });

    await Future<void>.delayed(const Duration(milliseconds: 300));
    holder.db.execute('COMMIT');

    expect(await capture, 'written while the app was busy');
    expect(
      SqliteNoteRepository(holder).listTimeline().map((n) => n.content),
      contains('written while the app was busy'),
    );
    holder.close();
  });

  test('only a busy database is retried', () {
    final db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    addTearDown(db.close);
    db.db.beginImmediate();
    // Already inside a transaction: a real error, thrown at once.
    final waited = Stopwatch()..start();
    expect(() => db.db.beginImmediate(), throwsA(isA<SqliteException>()));
    expect(waited.elapsed, lessThan(const Duration(seconds: 1)));
    db.db.execute('ROLLBACK');
  });

  test('a writer that never lets go still fails, after the patience', () {
    final path = p.join(tmp.path, 'nex.sqlite');
    final holder = NexDatabase.open(path);
    final waiter = NexDatabase.open(path);
    addTearDown(() {
      waiter.close();
      holder.close();
    });
    holder.db.beginImmediate();
    waiter.db.execute('PRAGMA busy_timeout = 0;');
    expect(
      () =>
          waiter.db.beginImmediate(patience: const Duration(milliseconds: 200)),
      throwsA(
        isA<SqliteException>().having(
          (e) => e.resultCode,
          'resultCode',
          SqlError.SQLITE_BUSY,
        ),
      ),
    );
    holder.db.execute('ROLLBACK');
  });
}
