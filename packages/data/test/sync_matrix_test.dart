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
        final reset = await http.post(Uri.parse('$baseUrl/sync/test/reset'));
        expect(
          reset.statusCode,
          200,
          reason: 'enable NEX_TEST_MODE=1 on backend for matrix isolation',
        );
      });

      test('1) concurrent content edit: later updated_at wins; no duplicate',
          () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl);
        final b = _Device(id: 'device-b', baseUrl: baseUrl);
        addTearDown(a.close);
        addTearDown(b.close);

        final note = a.captureText('v0');
        await a.sync();
        await b.sync();

        a.repo.updateContentAt(
          note.id,
          'from A',
          DateTime.utc(2026, 7, 1, 10),
        );
        b.repo.updateContentAt(
          note.id,
          'from B',
          DateTime.utc(2026, 7, 1, 11),
        );

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
        final a = _Device(id: 'device-a', baseUrl: baseUrl);
        final b = _Device(id: 'device-b', baseUrl: baseUrl);
        addTearDown(a.close);
        addTearDown(b.close);

        final note = a.captureText('original');
        await a.sync();
        await b.sync();

        final work = a.repo.upsertTag(name: 'work');
        a.repo.attachTag(noteId: note.id, tagId: work.id);
        a.repo.db.execute(
          "UPDATE notes SET updated_at = ? WHERE id = ?",
          [DateTime.utc(2026, 7, 2, 10).toIso8601String(), note.id],
        );

        b.repo.updateContentAt(
          note.id,
          'edited on B',
          DateTime.utc(2026, 7, 2, 11),
        );

        await a.sync();
        await b.sync();
        await a.sync();

        final aNote = a.repo.getById(note.id)!;
        final bNote = b.repo.getById(note.id)!;
        expect(aNote.content, 'edited on B');
        expect(bNote.content, 'edited on B');
        expect(aNote.tags.map((t) => t.name), contains('work'));
        expect(
          bNote.tags.map((t) => t.name),
          contains('work'),
          reason: 'ADR-020: tag must not be lost to whole-record LWW',
        );
      });

      test('3) tag add on A + different tag remove on B: union-merge', () async {
        final a = _Device(id: 'device-a', baseUrl: baseUrl);
        final b = _Device(id: 'device-b', baseUrl: baseUrl);
        addTearDown(a.close);
        addTearDown(b.close);

        final note = a.captureText('tagged');
        final alpha = a.repo.upsertTag(name: 'alpha');
        final beta = a.repo.upsertTag(name: 'beta');
        a.repo.attachTag(noteId: note.id, tagId: alpha.id);
        a.repo.attachTag(noteId: note.id, tagId: beta.id);
        a.repo.db.execute(
          "UPDATE notes SET sync_state = 'pending', updated_at = ? WHERE id = ?",
          [DateTime.utc(2026, 7, 3, 9).toIso8601String(), note.id],
        );
        await a.sync();
        await b.sync();

        final gamma = a.repo.upsertTag(name: 'gamma');
        a.repo.attachTag(noteId: note.id, tagId: gamma.id);
        a.repo.db.execute(
          "UPDATE notes SET updated_at = ? WHERE id = ?",
          [DateTime.utc(2026, 7, 3, 10).toIso8601String(), note.id],
        );

        final betaOnB = b.repo.listTags().firstWhere((t) => t.name == 'beta');
        b.repo.detachTag(noteId: note.id, tagId: betaOnB.id);
        b.repo.db.execute(
          "UPDATE notes SET updated_at = ? WHERE id = ?",
          [DateTime.utc(2026, 7, 3, 11).toIso8601String(), note.id],
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
        final a = _Device(id: 'device-a', baseUrl: baseUrl);
        final b = _Device(id: 'device-b', baseUrl: baseUrl);
        addTearDown(a.close);
        addTearDown(b.close);

        final note = a.captureText('doomed');
        await a.sync();
        await b.sync();

        a.repo.softDelete(note.id);
        b.repo.updateContentAt(
          note.id,
          'still editing',
          DateTime.utc(2026, 7, 4, 12),
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
        final a = _Device(id: 'device-a', baseUrl: baseUrl);
        final b = _Device(id: 'device-b', baseUrl: baseUrl);
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
        final a = _Device(id: 'device-a', baseUrl: baseUrl);
        final b = _Device(id: 'device-b', baseUrl: baseUrl);
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
    },
    skip: runMatrix ? false : 'set RUN_SYNC_MATRIX=1 with live Phase 2 backend',
  );
}

class _Device {
  _Device({required this.id, required this.baseUrl})
      : db = NexDatabase.openInMemory() {
    repo = NoteRepository(db, localDeviceId: id);
    client = SyncClient(baseUrl: baseUrl, deviceId: id, repo: repo);
  }

  final String id;
  final String baseUrl;
  final NexDatabase db;
  late final NoteRepository repo;
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
