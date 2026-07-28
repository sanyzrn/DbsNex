import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

/// Phase 2 §2.3 — mandatory six-row matrix against real SyncClient + backend.
///
/// Run with:
///   RUN_SYNC_MATRIX=1 SYNC_BASE_URL=http://127.0.0.1:4000 dart test test/sync_matrix_test.dart
/// Backend must have `NEX_TEST_MODE=1` (exposes `/sync/test/reset`).
void main() {
  final baseUrl =
      Platform.environment['SYNC_BASE_URL'] ?? 'http://127.0.0.1:4000';
  final runMatrix = Platform.environment['RUN_SYNC_MATRIX'] == '1';

  // The sync API stopped being open when tenancy landed. Each device pairs with
  // its own token, and the server rejects a push whose device_id is not the
  // caller's, so the matrix needs one token per simulated device.
  final tokens = <String, String?>{
    'device-a': Platform.environment['SYNC_TOKEN_DEVICE_A'],
    'device-b': Platform.environment['SYNC_TOKEN_DEVICE_B'],
  };

  group(
    'Phase 2 sync matrix (live backend)',
    () {
      setUpAll(() async {
        final health = await http.get(Uri.parse('$baseUrl/health'));
        if (health.statusCode != 200) {
          fail('backend not healthy at $baseUrl: ${health.statusCode}');
        }
        final body = jsonDecode(health.body) as Map<String, dynamic>;
        expect(body['phase'], 2, reason: 'backend must be Phase 2');
        expect(body['database'], 'up');
      });

      setUp(() async {
        // /sync/test/reset sits behind the same auth middleware as the rest of
        // the API. SyncClient authenticates now, but this raw call did not, so
        // every case still died in setUp with a 401.
        final reset = await http.post(
          Uri.parse('$baseUrl/sync/test/reset'),
          headers: {
            if (tokens['device-a'] != null)
              'authorization': 'Bearer ${tokens['device-a']}',
          },
        );
        expect(
          reset.statusCode,
          200,
          reason: 'enable NEX_TEST_MODE=1 on backend for matrix isolation',
        );
      });

      test('1) concurrent content edit: later updated_at wins; no duplicate',
          () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        final note = a.captureText('v0');
        await a.sync();
        await b.sync();

        final tA = DateTime.now().toUtc().add(const Duration(seconds: 1));
        final tB = DateTime.now().toUtc().add(const Duration(seconds: 2));
        a.repo.updateContentAt(note.id, 'from A', tA);
        b.repo.updateContentAt(note.id, 'from B', tB);

        await a.sync();
        await b.sync();
        await a.sync();

        final aNote = a.repo.getById(note.id)!;
        final bNote = b.repo.getById(note.id)!;
        expect(aNote.content, 'from B');
        expect(bNote.content, 'from B');
        expect(a.repo.listTimeline().where((n) => n.id == note.id).length, 1);
        expect(b.repo.listTimeline().where((n) => n.id == note.id).length, 1);
      });

      test('2) tag add on A + content edit on B: BOTH survive', () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        final note = a.captureText('original');
        await a.sync();
        await b.sync();

        final work = a.repo.upsertTag(name: 'work');
        a.repo.attachTag(noteId: note.id, tagId: work.id);
        final tTag = DateTime.now().toUtc().add(const Duration(seconds: 1));
        a.repo.db.execute(
          "UPDATE notes SET updated_at = ? WHERE id = ?",
          [tTag.toIso8601String(), note.id],
        );

        b.repo.updateContentAt(
          note.id,
          'edited on B',
          DateTime.now().toUtc().add(const Duration(seconds: 2)),
        );

        await a.sync();
        await b.sync();
        await a.sync();

        final aNote = a.repo.getById(note.id)!;
        final bNote = b.repo.getById(note.id)!;
        expect(aNote.content, 'edited on B');
        expect(bNote.content, 'edited on B');
        // Case-insensitive: tag names dedupe with COLLATE NOCASE, so adding
        // "work" resolves to the existing seeded "Work" rather than making a
        // second tag. What this test is about is that the tag survives the
        // merge, not how it is capitalised.
        expect(
          aNote.tags.map((t) => t.name.toLowerCase()),
          contains('work'),
        );
        expect(
          bNote.tags.map((t) => t.name.toLowerCase()),
          contains('work'),
          reason: 'ADR-020: tag must not be lost to whole-record LWW',
        );
      });

      test('3) tag add on A + different tag remove on B: union-merge', () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        final note = a.captureText('tagged');
        final alpha = a.repo.upsertTag(name: 'alpha');
        final beta = a.repo.upsertTag(name: 'beta');
        a.repo.attachTag(noteId: note.id, tagId: alpha.id);
        a.repo.attachTag(noteId: note.id, tagId: beta.id);
        final t0 = DateTime.now().toUtc();
        a.repo.db.execute(
          "UPDATE notes SET sync_state = 'pending', updated_at = ? WHERE id = ?",
          [t0.toIso8601String(), note.id],
        );
        await a.sync();
        await b.sync();

        final gamma = a.repo.upsertTag(name: 'gamma');
        a.repo.attachTag(noteId: note.id, tagId: gamma.id);
        a.repo.db.execute(
          "UPDATE notes SET updated_at = ? WHERE id = ?",
          [t0.add(const Duration(seconds: 1)).toIso8601String(), note.id],
        );

        final betaOnB = b.repo.listTags().firstWhere((t) => t.name == 'beta');
        b.repo.detachTag(noteId: note.id, tagId: betaOnB.id);
        b.repo.db.execute(
          "UPDATE notes SET updated_at = ? WHERE id = ?",
          [t0.add(const Duration(seconds: 2)).toIso8601String(), note.id],
        );

        await a.sync();
        await b.sync();
        await a.sync();

        final names = a.repo.getById(note.id)!.tags.map((t) => t.name).toSet();
        expect(names, contains('gamma'), reason: 'added tag must survive');
        expect(names, contains('alpha'));
        // ADR-020 union: B removed beta while A still held it → beta remains.
        expect(
          names,
          contains('beta'),
          reason: 'union-merge: tag not silently dropped from the other side',
        );
        expect(b.repo.getById(note.id)!.tags.map((t) => t.name).toSet(), names);
      });

      test('4) delete on A vs edit on B: tombstone wins', () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        final note = a.captureText('doomed');
        await a.sync();
        await b.sync();

        a.repo.softDelete(note.id);
        b.repo.updateContentAt(
          note.id,
          'still editing',
          DateTime.now().toUtc().add(const Duration(seconds: 2)),
        );

        await a.sync();
        await b.sync();
        await a.sync();

        expect(a.repo.getById(note.id), isNull);
        expect(b.repo.getById(note.id), isNull);
        expect(
          a.repo.getById(note.id, includeDeleted: true)?.deletedAt,
          isNotNull,
        );
        expect(
          b.repo.getById(note.id, includeDeleted: true)?.deletedAt,
          isNotNull,
        );
      });

      test('5) identical media_hash deduped — not stored twice', () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        final bytes = Uint8List.fromList(utf8.encode('same-photo-bytes'));
        final hash = sha256OfBytes(bytes);

        a.repo.insert(
          Note(
            id: newUuidV7(),
            type: NoteType.photo,
            mediaUri: 'file:///a/photo.jpg',
            mediaHash: hash,
            createdAt: DateTime.utc(2026, 7, 5, 10),
            updatedAt: DateTime.utc(2026, 7, 5, 10),
            deviceId: a.id,
            rev: 1,
            syncState: SyncState.pending,
          ),
        );
        final r1 = await a.sync();
        expect(r1.mediaDeduped, isEmpty);

        b.repo.insert(
          Note(
            id: newUuidV7(),
            type: NoteType.photo,
            mediaUri: 'file:///b/photo.jpg',
            mediaHash: hash,
            createdAt: DateTime.utc(2026, 7, 5, 11),
            updatedAt: DateTime.utc(2026, 7, 5, 11),
            deviceId: b.id,
            rev: 1,
            syncState: SyncState.pending,
          ),
        );
        final r2 = await b.sync();
        expect(r2.mediaDeduped, contains(hash));

        await a.sync();
        expect(
          a.repo.listTimeline().where((n) => n.mediaHash == hash).length,
          2,
        );
      });

      test('6) long offline then reconnect: outbox flushes, no loss/dupes',
          () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        final online = b.captureText('online-1');
        await b.sync();

        final offlineNotes = <Note>[
          for (var i = 0; i < 5; i++) a.captureText('offline-$i'),
        ];
        final online2 = b.captureText('online-2');
        await b.sync();

        await a.sync();
        await b.sync();
        await a.sync();

        final aIds = a.repo.listTimeline().map((n) => n.id).toSet();
        final bIds = b.repo.listTimeline().map((n) => n.id).toSet();
        expect(aIds, equals(bIds));
        expect(aIds, containsAll(offlineNotes.map((n) => n.id)));
        expect(aIds, containsAll([online.id, online2.id]));
        expect(aIds.length, offlineNotes.length + 2);
      });

      /* ------------------------------------------------- transport, not merge */
      //
      // Everything above asserts that two devices agree. None of it can fail on
      // a broken cursor, a discarded push response, an ignored `has_more` or a
      // dropped tag remap, because a full re-download converges just as well as
      // an incremental pull and the suite never looked at the wire. These do.

      test('7) pull is incremental: the second cycle sends a cursor', () async {
        final recorder = _Recording(http.Client());
        final a = _Device(
          id: 'device-a',
          baseUrl: baseUrl,
          bearerToken: tokens['device-a'],
          recorder: recorder,
        );
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        // Something from another device, so A's pull has a row to advance on.
        b.captureText('from b');
        await b.sync();
        await a.sync();

        recorder.requests.clear();
        await a.sync();

        final pulls = recorder.requests.where((u) => u.path.endsWith('/sync/pull'));
        expect(pulls, isNotEmpty, reason: 'the cycle must pull');
        final since = pulls.last.queryParameters['since'];
        expect(since, isNotNull, reason: 'no cursor means a full re-download');
        expect(int.parse(since!), greaterThan(0));
      });

      test('8) the cursor survives a cold start', () async {
        // The watermark used to live in a field on the client, so even with the
        // right field name every launch restarted the pull from zero.
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(b.close);
        b.captureText('seed');
        await b.sync();

        final first = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        await first.sync();
        final carried = first.repo.syncCursor;
        first.close();

        expect(carried, isNotNull);
        expect(int.parse(carried!), greaterThan(0));
      });

      test('9) a change set larger than one page drains completely', () async {
        final pageSize = int.parse(
          Platform.environment['SYNC_PAGE_SIZE'] ?? '500',
        );
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        // Two full pages and a bit, so `has_more` is true more than once.
        final total = pageSize * 2 + 3;
        for (var i = 0; i < total; i++) {
          b.captureText('bulk-$i');
        }
        await b.sync();
        await a.sync();

        expect(
          a.repo.listTimeline(limit: total + 10).length,
          total,
          reason: 'a client that reads one page leaves the rest behind forever',
        );
      });

      test('10) the same tag name minted on both devices converges to one id',
          () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        // Independently created, so the two devices mint different UUIDs for
        // one name — the case tag_remap exists for, and the one the matrix
        // could never reach because both sides took their tags from A.
        final onA = a.repo.upsertTag(name: 'zzz-ideas');
        final onB = b.repo.upsertTag(name: 'zzz-ideas');
        expect(onA.id, isNot(onB.id), reason: 'the premise of this test');

        final noteA = a.captureText('a note');
        a.repo.attachTag(noteId: noteA.id, tagId: onA.id);
        final noteB = b.captureText('b note');
        b.repo.attachTag(noteId: noteB.id, tagId: onB.id);

        await a.sync();
        await b.sync();
        await a.sync();

        final aTags = a.repo.listTags().where((t) => t.name == 'zzz-ideas');
        final bTags = b.repo.listTags().where((t) => t.name == 'zzz-ideas');
        expect(aTags, hasLength(1), reason: 'a remap that is ignored duplicates');
        expect(bTags, hasLength(1));
        expect(
          aTags.first.id,
          bTags.first.id,
          reason: 'both devices must land on the server canonical id',
        );
        // And the join must still point at a row that exists.
        expect(b.repo.tagsForNote(noteB.id).map((t) => t.id), [bTags.first.id]);
      });

      test('11) a write the server refuses stays in the outbox', () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final b = _Device(id: 'device-b', baseUrl: baseUrl, bearerToken: tokens['device-b']);
        addTearDown(a.close);
        addTearDown(b.close);

        final note = a.captureText('v0');
        await a.sync();
        await b.sync();

        // B advances the revision twice while A is offline, so A's next push
        // carries a revision the server has already passed.
        b.repo.updateContentAt(
          note.id,
          'b1',
          DateTime.now().toUtc().add(const Duration(seconds: 1)),
        );
        await b.sync();
        b.repo.updateContentAt(
          note.id,
          'b2',
          DateTime.now().toUtc().add(const Duration(seconds: 2)),
        );
        await b.sync();

        // A edits from its stale revision. The server must refuse it.
        a.repo.updateContentAt(
          note.id,
          'a1',
          DateTime.now().toUtc().subtract(const Duration(seconds: 10)),
        );
        final pendingBefore = a.repo.listPending().map((n) => n.id).toSet();
        expect(pendingBefore, contains(note.id));

        final result = await a.sync();

        // Either the server took it (and said so) or it refused it (and the
        // note is still in the outbox to be retried). What must never happen is
        // the third thing: refused, and cleared from the outbox anyway.
        final stillPending = a.repo.listPending().map((n) => n.id).toSet();
        if (!result.mergedIds.contains(note.id)) {
          expect(
            stillPending,
            contains(note.id),
            reason: 'a refused write that leaves the outbox is a lost edit',
          );
        } else {
          expect(stillPending, isNot(contains(note.id)));
        }
      });

      test('12) the push response is read at all', () async {
        // `mergedIds` was decoded from a key the server stopped sending, so it
        // was always empty and nothing noticed.
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        addTearDown(a.close);

        final note = a.captureText('acknowledge me');
        final result = await a.sync();

        expect(result.mergedIds, contains(note.id));
        expect(result.pushed, greaterThan(0));
      });

      test('13) an unchanged tag is not re-broadcast on every sync', () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl, bearerToken: tokens['device-a']);
        final recorder = _Recording(http.Client());
        final b = _Device(
          id: 'device-b',
          baseUrl: baseUrl,
          bearerToken: tokens['device-b'],
          recorder: recorder,
        );
        addTearDown(a.close);
        addTearDown(b.close);

        a.repo.upsertTag(name: 'zzz-stable');
        await a.sync();
        await b.sync();

        // Nothing has changed. A sync from A must not move any tag's sequence,
        // so B's next pull must bring back no tags at all. Before, every sync
        // re-sequenced the entire tag table and every peer re-downloaded it.
        await a.sync();
        final before = b.repo.syncCursor;
        await b.sync();

        expect(
          b.repo.syncCursor,
          before,
          reason: 'an idle sync moved the watermark, so something was rewritten',
        );
      });
    },
    skip: runMatrix ? false : 'set RUN_SYNC_MATRIX=1 with live Phase 2 backend',
  );
}

/// An http.Client that remembers every URI it was asked for.
///
/// Convergence between two devices is satisfied just as well by a full
/// re-download as by a correct incremental pull, so the outcome cannot tell
/// them apart — only the request can. This is what makes the incrementality
/// test able to fail.
class _Recording extends http.BaseClient {
  _Recording(this._inner);

  final http.Client _inner;
  final List<Uri> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request.url);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class _Device {
  _Device({
    required this.id,
    required this.baseUrl,
    this.bearerToken,
    this.recorder,
  }) : db = NexDatabase.openInMemory() {
    repo = SqliteNoteRepository(db, localDeviceId: id);
    client = SyncClient(
      baseUrl: baseUrl,
      deviceId: id,
      repo: repo,
      bearerToken: bearerToken,
      httpClient: recorder,
    );
  }

  final String id;
  final String baseUrl;
  final String? bearerToken;
  final _Recording? recorder;
  final NexDatabase db;
  late final SqliteNoteRepository repo;
  late final SyncClient client;

  Note captureText(String content) {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: content,
        createdAt: now,
        updatedAt: now,
        deviceId: id,
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  Future<SyncResult> sync() => client.sync();

  void close() {
    client.close();
    db.close();
  }
}
