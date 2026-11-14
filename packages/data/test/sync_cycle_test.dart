import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The cycle-level behaviour of [SyncClient] against a scripted transport —
/// what the live matrix cannot pin because it needs a broken server to see:
/// a refused push that must not stop the pull, an idle outbox that must not
/// push at all, an unknown note type that must not wedge the cursor, and the
/// two halves of media transfer (upload before push, download after pull).
///
/// Run with: dart test test/sync_cycle_test.dart

/// Answers each request from [respond]; records everything asked.
class _Scripted extends http.BaseClient {
  _Scripted(this.respond);

  final http.Response Function(http.Request request) respond;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final recorded = request as http.Request;
    requests.add(recorded);
    final response = respond(recorded);
    final bytes = response.bodyBytes;
    return http.StreamedResponse(
      Stream<Uint8List>.fromIterable([bytes]),
      response.statusCode,
      contentLength: bytes.length,
    );
  }
}

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_sync_cycle_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
    // A new library seeds its starter tags as pending — the first real sync
    // pushes them. These cases are about the notes, so the starters start
    // out as already sent.
    repo.markTagsSynced(repo.listPendingTags().map((tag) => tag.id));
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  SyncClient clientFor(http.Client transport, {String? mediaDir}) => SyncClient(
    baseUrl: 'https://sync.invalid',
    deviceId: 'device-a',
    repo: repo,
    mediaDir: mediaDir,
    httpClient: transport,
    // No case here is about patience; the default would only make a
    // mis-routed request expensive to notice.
    requestTimeout: const Duration(seconds: 2),
  );

  Note pendingNote({
    String? id,
    NoteType type = NoteType.text,
    String? content,
    String? mediaUri,
    String? mediaHash,
    int? durationMs,
  }) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id ?? newUuidV7(),
      type: type,
      content: content,
      mediaUri: mediaUri,
      mediaHash: mediaHash,
      durationMs: durationMs,
      createdAt: now,
      updatedAt: now,
      deviceId: 'device-a',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  /// A pull page with [notes], cursor '5', no more pages.
  String pullBody(List<Map<String, Object?>> notes) => jsonEncode({
    'notes': notes,
    'tags': const <Object>[],
    'cursor': '5',
    'has_more': false,
  });

  String pushBody(Map<String, Object?> body) => jsonEncode(body);

  Map<String, Object?> remoteNote(
    String id,
    String content, {
    String deviceId = 'device-b',
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'id': id,
      'type': 'text',
      'content': content,
      'media_uri': null,
      'media_hash': null,
      'duration_ms': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': deviceId,
      'rev': 1,
      'tag_ids': const <String>[],
    };
  }

  test('an idle outbox pushes nothing and still pulls', () async {
    final transport = _Scripted(
      (request) => request.method == 'GET'
          ? http.Response(pullBody([]), 200)
          : fail(
              'no request but the pull was expected, got '
              '${request.method} ${request.url}',
            ),
    );

    final result = await clientFor(transport).sync();

    expect(result.pushed, 0);
    expect(result.pulled, 0);
    expect(transport.requests.map((r) => r.method), [
      'GET',
    ], reason: 'an empty outbox used to send one pointless push request');
  });

  test('a refused push does not stop the pull', () async {
    // The exact case the push-before-pull order risked: one item the server
    // will not take must not cost the device everything the server could
    // give it. The error still surfaces — after the pull, not instead of it.
    final local = repo.insert(pendingNote(content: 'never accepted'));
    final remote = newUuidV7();

    final transport = _Scripted((request) {
      if (request.method == 'POST') return http.Response('nope', 400);
      if (request.method == 'GET') {
        return http.Response(
          pullBody([remoteNote(remote, 'from a peer')]),
          200,
        );
      }
      fail('unexpected ${request.method} ${request.url}');
    });

    await expectLater(clientFor(transport).sync(), throwsA(isA<StateError>()));

    expect(transport.requests.map((r) => r.method), ['POST', 'GET']);
    expect(
      repo.getById(remote)?.content,
      'from a peer',
      reason: 'the pull ran despite the refused push',
    );
    expect(
      repo.listPending().map((n) => n.id),
      contains(local.id),
      reason: 'an unacknowledged push leaves the outbox intact',
    );
  });

  test('a note with an unknown type is skipped, not fatal', () async {
    final known = newUuidV7();
    final unknown = newUuidV7();
    final ahead = newUuidV7();
    final now = DateTime.now().toUtc().toIso8601String();
    Map<String, Object?> asType(String id, String type) => {
      'id': id,
      'type': type,
      'content': 'the $type one',
      'media_uri': null,
      'media_hash': null,
      'duration_ms': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': 'device-b',
      'rev': 1,
      'tag_ids': const <String>[],
    };

    final transport = _Scripted(
      (request) => http.Response(
        pullBody([
          asType(unknown, 'hologram'),
          asType(known, 'text'),
          asType(ahead, 'text'),
        ]),
        200,
      ),
    );

    final result = await clientFor(transport).sync();

    expect(result.skippedUnknownTypes, 1);
    expect(repo.getById(known)?.content, 'the text one');
    expect(repo.getById(ahead)?.content, 'the text one');
    expect(
      repo.getById(unknown),
      isNull,
      reason: 'a type this build cannot name is not inventable locally',
    );
    expect(
      repo.syncCursor,
      '5',
      reason:
          'the cursor must advance past the skipped note, or every '
          'later cycle re-fails on it',
    );
  });

  test(
    'per-item rejections stay in the outbox and surface in the result',
    () async {
      final stuck = repo.insert(pendingNote(content: 'not mine to push'));

      final transport = _Scripted((request) {
        if (request.method == 'POST') {
          return http.Response(
            pushBody({
              'merged': const <Object>[],
              'media_deduped': const <Object>[],
              'tag_remap': const <Object>[],
              'rejected': [
                {'id': stuck.id, 'reason': 'foreign_id'},
              ],
              'cursor': '0',
            }),
            200,
          );
        }
        return http.Response(pullBody([]), 200);
      });

      final result = await clientFor(transport).sync();

      expect(result.rejected, [stuck.id]);
      expect(
        repo.listPending().map((n) => n.id),
        contains(stuck.id),
        reason: 'a rejected item is retried, never silently dropped',
      );
    },
  );

  test('a large outbox splits by payload size, not only item count', () async {
    // Three ~200 KB notes fit the 500-item cap as one request, and used to
    // go out as one — past the route's 2 MB limit for large-enough notes.
    final big = 'x' * 200 * 1024;
    for (var i = 0; i < 3; i++) {
      repo.insert(pendingNote(content: '$big $i'));
    }

    var pushes = 0;
    final transport = _Scripted((request) {
      if (request.method == 'POST') {
        pushes++;
        return http.Response(
          pushBody({
            'merged': const <Object>[],
            'media_deduped': const <Object>[],
            'tag_remap': const <Object>[],
            'rejected': const <Object>[],
            'cursor': '0',
          }),
          200,
        );
      }
      return http.Response(pullBody([]), 200);
    });

    await clientFor(transport).sync();

    expect(
      pushes,
      2,
      reason: 'three 200 KB notes exceed the 512 KB budget as one payload',
    );
    for (final request in transport.requests) {
      expect(
        request.bodyBytes.length,
        lessThan(600 * 1024),
        reason: 'every request stays under the route body limit',
      );
    }
  });

  test('a local media file survives its own echo', () {
    // The wire carries a portable file name now. When the author's own note
    // comes back, the local absolute path must survive the apply — or the
    // echo of a write would orphan the very file it describes.
    final mediaRoot = Directory(p.join(tmp.path, 'media'))..createSync();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final file = File(p.join(mediaRoot.path, 'photo.jpg'))
      ..writeAsBytesSync(bytes);
    final hash = sha256OfBytes(bytes);
    final now = DateTime.now().toUtc();

    final note = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        mediaUri: file.path,
        mediaHash: hash,
        createdAt: now,
        updatedAt: now,
        deviceId: 'device-a',
        rev: 1,
        syncState: SyncState.synced,
      ),
    );

    repo.applyRemoteNote(
      id: note.id,
      type: NoteType.photo,
      content: null,
      mediaUri: 'photo.jpg',
      mediaHash: hash,
      durationMs: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      deviceId: 'device-a',
      rev: 1,
      tagIds: const [],
    );

    expect(repo.getById(note.id)?.mediaUri, file.path);
  });

  test('pending media uploads before its note pushes', () async {
    final mediaRoot = Directory(p.join(tmp.path, 'media'))..createSync();
    final bytes = Uint8List.fromList(utf8.encode('a tiny voice note'));
    final hash = sha256OfBytes(bytes);
    final file = File(p.join(mediaRoot.path, 'voice.m4a'))
      ..writeAsBytesSync(bytes);

    final note = repo.insert(
      pendingNote(
        type: NoteType.voice,
        mediaUri: file.path,
        mediaHash: hash,
        durationMs: 1000,
      ),
    );

    final transport = _Scripted((request) {
      if (request.method == 'PUT') return http.Response('', 204);
      if (request.method == 'POST') {
        return http.Response(
          pushBody({
            'merged': [
              {'id': note.id, 'rev': 1},
            ],
            'media_deduped': const <Object>[],
            'tag_remap': const <Object>[],
            'rejected': const <Object>[],
            'cursor': '0',
          }),
          200,
        );
      }
      return http.Response(pullBody([]), 200);
    });

    await clientFor(transport, mediaDir: mediaRoot.path).sync();

    // The bytes went up first, under their own content hash…
    expect(transport.requests.first.method, 'PUT');
    expect(transport.requests.first.url.path, endsWith('/sync/media/$hash'));
    expect(transport.requests.first.bodyBytes, bytes);
    // …and the note's push named the portable file, never this device's path.
    final pushed = transport.requests.firstWhere((r) => r.method == 'POST');
    final body = jsonDecode(pushed.body) as Map<String, dynamic>;
    final notes = body['notes'] as List;
    expect(notes, hasLength(1));
    expect(notes.first['media_uri'], 'voice.m4a');
    expect(notes.first['media_uri'], isNot(contains(mediaRoot.path)));
    expect(
      repo.listPending(),
      isEmpty,
      reason: 'the acknowledged write left the outbox',
    );
  });

  test('a pulled note fetches its missing media', () async {
    final mediaRoot = Directory(p.join(tmp.path, 'media'))..createSync();
    final bytes = Uint8List.fromList(utf8.encode('a peer photo'));
    final hash = sha256OfBytes(bytes);
    final id = newUuidV7();
    final now = DateTime.now().toUtc().toIso8601String();

    final transport = _Scripted((request) {
      if (request.method == 'GET' && request.url.path.contains('/media/')) {
        return http.Response.bytes(bytes, 200);
      }
      if (request.method == 'GET') {
        return http.Response(
          pullBody([
            {
              'id': id,
              'type': 'photo',
              'content': null,
              'media_uri': 'pic.jpg',
              'media_hash': hash,
              'duration_ms': null,
              'created_at': now,
              'updated_at': now,
              'deleted_at': null,
              'device_id': 'device-b',
              'rev': 1,
              'tag_ids': const <String>[],
            },
          ]),
          200,
        );
      }
      fail('unexpected ${request.method} ${request.url}');
    });

    await clientFor(transport, mediaDir: mediaRoot.path).sync();

    final note = repo.getById(id);
    expect(note, isNotNull, reason: 'the pulled note applied');
    final fetched = File(note!.mediaUri!);
    expect(fetched.existsSync(), isTrue, reason: 'the bytes landed locally');
    expect(sha256OfBytes(fetched.readAsBytesSync()), hash);
    expect(p.extension(fetched.path), '.jpg');
    expect(
      p.isWithin(mediaRoot.path, fetched.path),
      isTrue,
      reason: 'downloaded media files into the media tree',
    );
  });

  test('media bytes that do not hash to their address are discarded', () async {
    final mediaRoot = Directory(p.join(tmp.path, 'media'))..createSync();
    final lying = Uint8List.fromList(utf8.encode('not what the hash says'));
    final hash = sha256OfBytes(Uint8List.fromList(utf8.encode('real bytes')));
    final id = newUuidV7();
    final now = DateTime.now().toUtc().toIso8601String();

    final transport = _Scripted((request) {
      if (request.method == 'GET' && request.url.path.contains('/media/')) {
        return http.Response.bytes(lying, 200);
      }
      if (request.method == 'GET') {
        return http.Response(
          pullBody([
            {
              'id': id,
              'type': 'photo',
              'content': null,
              'media_uri': 'pic.jpg',
              'media_hash': hash,
              'duration_ms': null,
              'created_at': now,
              'updated_at': now,
              'deleted_at': null,
              'device_id': 'device-b',
              'rev': 1,
              'tag_ids': const <String>[],
            },
          ]),
          200,
        );
      }
      fail('unexpected ${request.method} ${request.url}');
    });

    await clientFor(transport, mediaDir: mediaRoot.path).sync();

    expect(
      repo.getById(id)?.mediaUri,
      'pic.jpg',
      reason: 'a body that does not hash to its address is written nowhere',
    );
    expect(mediaRoot.listSync(), isEmpty);
  });
}
