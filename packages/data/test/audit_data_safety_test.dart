import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  setUp(() {
    root = Directory.systemTemp.createTempSync('nex-audit-data-');
    db = NexDatabase.open(p.join(root.path, 'db.sqlite'));
    repo = SqliteNoteRepository(db);
  });
  tearDown(() {
    db.close();
    root.deleteSync(recursive: true);
  });
  Note local() => repo.insert(
    Note(
      id: newUuidV7(),
      type: NoteType.text,
      content: 'unsent local text',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 2),
      deviceId: 'local',
      rev: 1,
      syncState: SyncState.pending,
    ),
  );
  void remote(Note note, {DateTime? deletedAt}) => repo.applyRemoteNote(
    id: note.id,
    type: NoteType.text,
    content: 'remote text',
    createdAt: note.createdAt,
    updatedAt: DateTime.utc(2026, 3),
    deviceId: 'remote',
    rev: 8,
    tagIds: [],
    deletedAt: deletedAt,
  );
  test('pending text, caption and tags survive as a conflict copy', () {
    final note = local();
    repo.setCaption(note.id, 'local caption');
    final tag = repo.upsertTag(name: 'Local');
    repo.attachTag(noteId: note.id, tagId: tag.id);
    remote(note);
    final notes = repo.listTimeline();
    expect(
      notes.map((n) => n.content),
      containsAll(['unsent local text', 'remote text']),
    );
    final preserved = notes.singleWhere((n) => n.id != note.id);
    expect(preserved.caption, 'local caption');
    expect(preserved.tags.single.id, tag.id);
    expect(preserved.syncState, SyncState.pending);
    expect(repo.getById(note.id)!.tags.single.id, tag.id);
    expect(repo.getById(note.id)!.rev, 8);
    // A second identical pull consumes the republished union, without
    // inventing another conflict copy.
    remote(note);
    expect(repo.listTimeline(), hasLength(2));
  });
  test('remote deletion retains unsent text and the remote tombstone', () {
    final note = local();
    remote(note, deletedAt: DateTime.utc(2026, 3));
    expect(repo.getById(note.id), isNull);
    expect(repo.getById(note.id, includeDeleted: true)!.isDeleted, isTrue);
    expect(repo.listTimeline().single.content, 'unsent local text');
  });
  test('a pending local deletion is not resurrected by a remote live row', () {
    final note = local();
    repo.softDelete(note.id);
    remote(note);
    final tombstone = repo.getById(note.id, includeDeleted: true)!;
    expect(tombstone.isDeleted, isTrue);
    expect(tombstone.syncState, SyncState.pending);
    expect(tombstone.rev, 8);
  });
  test('synced notes accept remote text without creating a copy', () {
    final note = local();
    repo.markSynced(note.id);
    remote(note);
    expect(repo.listTimeline().single.content, 'remote text');
  });
  test(
    'receipt cleanup protects live, fresh, profile and linked external files',
    () {
      final media = Directory(p.join(root.path, 'media'))..createSync();
      final receipts = Directory(p.join(media.path, 'recurring'))..createSync();
      File old(String path) => File(path)
        ..writeAsStringSync('photo')
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 3)),
        );
      final keep = old(p.join(receipts.path, 'keep.jpg'));
      final orphan = old(p.join(receipts.path, 'orphan.jpg'));
      final fresh = File(p.join(receipts.path, 'fresh.jpg'))
        ..writeAsStringSync('new');
      final profile = old(
        p.join(
          (Directory(p.join(media.path, 'profile'))..createSync()).path,
          'me.jpg',
        ),
      );
      final outside = old(p.join(root.path, 'outside.jpg'));
      Link(p.join(receipts.path, 'link.jpg')).createSync(outside.path);
      SqliteCommitmentRepository(db).save(
        NexCommitment(
          id: 'c',
          title: 'Bill',
          cadence: NexCadence.months,
          every: 1,
          dueAt: DateTime.utc(2026),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          details: {
            'receipts': ['recurring/keep.jpg'],
          },
        ),
      );
      final removed = LibraryMaintenance(
        repo,
        mediaRoot: media.path,
      ).sweepOrphanMedia();
      expect(removed, 1);
      expect(orphan.existsSync(), isFalse);
      for (final file in [keep, fresh, profile, outside]) {
        expect(file.existsSync(), isTrue);
      }
    },
  );
  test(
    'a rejected push followed by pull preserves both versions through SyncClient',
    () async {
      final note = local();
      final client = SyncClient(
        baseUrl: 'https://sync.invalid',
        deviceId: 'local',
        repo: repo,
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.method == 'POST'
                  ? {
                      'merged': <Object?>[],
                      'tag_remap': <Object?>[],
                      'media_deduped': <String>[],
                    }
                  : {
                      'cursor': '8',
                      'has_more': false,
                      'tags': <Object?>[],
                      'notes': [
                        {
                          'id': note.id,
                          'type': 'text',
                          'content': 'remote text',
                          'created_at': note.createdAt.toIso8601String(),
                          'updated_at': DateTime.utc(2026, 3).toIso8601String(),
                          'device_id': 'remote',
                          'rev': 8,
                          'tag_ids': <String>[],
                        },
                      ],
                    },
            ),
            200,
          ),
        ),
      );
      addTearDown(client.close);
      await client.sync();
      expect(
        repo.listTimeline().map((n) => n.content),
        containsAll(['unsent local text', 'remote text']),
      );
      expect(repo.listPending().single.content, 'unsent local text');
      expect(repo.syncCursor, '8');
    },
  );
  test('acknowledgement cannot clear a newer edit made during the push', () {
    final pushed = local();
    repo.updateContentAt(
      pushed.id,
      'edited while sending',
      DateTime.utc(2026, 4),
    );
    repo.markSynced(pushed.id, serverRev: 8, expected: pushed);
    expect(repo.getById(pushed.id)!.syncState, SyncState.pending);
    expect(repo.getById(pushed.id)!.content, 'edited while sending');
  });
}
