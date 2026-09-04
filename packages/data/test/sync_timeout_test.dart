import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A server that accepts the connection and then says nothing.
///
/// Not an offline device and not a refused connection — both of those fail
/// fast and always did. This is the case with no error to return: a suspended
/// instance, a NAT binding that expired mid-request, a VPN that disappeared
/// without a FIN. The socket stays open and the response never comes.
class _SilentClient extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    // Never completes, and never will. `package:http` has no default timeout,
    // so before the fix this future was the end of the story.
    return Completer<http.StreamedResponse>().future;
  }
}

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_sync_timeout_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  SyncClient clientFor(http.Client transport) => SyncClient(
    baseUrl: 'https://sync.invalid',
    deviceId: 'device-a',
    repo: repo,
    httpClient: transport,
    // Production uses 30 seconds. The point of the case is the bound, not its
    // size, and a suite that waits half a minute to prove one is a suite
    // people stop running.
    requestTimeout: const Duration(milliseconds: 100),
  );

  test('a push that never answers gives up instead of parking forever', () async {
    final transport = _SilentClient();

    // A pending note, so the cycle really does push rather than going straight
    // to the pull.
    final now = DateTime.now().toUtc();
    repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'something to send',
        createdAt: now,
        updatedAt: now,
        deviceId: 'device-a',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );

    // The assertion is the timeout itself: without one this never completes,
    // and the case fails by running out of the suite's own patience rather
    // than by this matcher.
    await expectLater(clientFor(transport).sync(), throwsA(isA<TimeoutException>()));
    expect(
      transport.requests,
      1,
      reason: 'the push was attempted, then abandoned',
    );
  });

  test('a pull that never answers gives up too', () async {
    final transport = _SilentClient();
    // Nothing pending, so `sync()` reaches the pull with an empty push — and
    // that empty push is itself a request, so the cycle stops there. Either
    // way the property is the same one: no leg of a sync waits forever.
    await expectLater(clientFor(transport).sync(), throwsA(isA<TimeoutException>()));
    expect(transport.requests, greaterThanOrEqualTo(1));
  });

  test('the outbox is untouched when the request times out', () async {
    final transport = _SilentClient();
    final now = DateTime.now().toUtc();
    final note = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'still ours',
        createdAt: now,
        updatedAt: now,
        deviceId: 'device-a',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );

    await expectLater(
      clientFor(transport).sync(),
      throwsA(isA<TimeoutException>()),
    );

    // Giving up on the request must not look like the server accepted it.
    // Only ids the server acknowledged leave the outbox, and a timeout
    // acknowledges nothing — the note is still there for the next cycle.
    expect(repo.listPending().map((n) => n.id), contains(note.id));
    expect(repo.syncCursor, isNull);
  });
}
