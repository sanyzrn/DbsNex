import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  setUp(() {
    root = Directory.systemTemp.createTempSync('nex_260_metadata_');
    db = NexDatabase.open('${root.path}/nex.sqlite');
    repo = SqliteNoteRepository(db, localDeviceId: 'test');
  });
  tearDown(() {
    db.close();
    root.deleteSync(recursive: true);
  });
  Note create(String content) =>
      CaptureService(repo, deviceId: 'test').submitTextCapture(content)!;

  test('urgent survives reopen, is independent of Pin and preserves order', () {
    final first = create('first');
    final second = create('second');
    repo.pinNote(first.id);
    final before = repo.listTimeline().map((n) => n.id).toList();
    final at = repo.getById(second.id)!.updatedAt;
    repo.setUrgent(second.id, true);
    repo.setUrgent(first.id, true);
    expect(repo.listTimeline().map((n) => n.id), before);
    expect(repo.getById(first.id)!.pinnedAt, isNotNull);
    expect(repo.getById(second.id)!.pinnedAt, isNull);
    expect(repo.getById(second.id)!.updatedAt, at);
    db.close();
    db = NexDatabase.open('${root.path}/nex.sqlite');
    repo = SqliteNoteRepository(db, localDeviceId: 'test');
    expect(repo.getById(first.id)!.isUrgent, isTrue);
    expect(repo.getById(second.id)!.isUrgent, isTrue);
    expect(repo.getById(first.id)!.copyWith(content: 'edit').isUrgent, isTrue);
    repo.setUrgent(first.id, false);
    expect(repo.getById(first.id)!.isUrgent, isFalse);
    expect(repo.getById(first.id)!.pinnedAt, isNotNull);
    expect(
      repo.search(const SearchFilters(query: 'first')).single.id,
      first.id,
    );
  });

  test('text caption is independent, searchable and part of AI source', () {
    final note = create('Original primary body.');
    repo.setCaption(note.id, 'Separate caption needle260.');
    final saved = repo.getById(note.id)!;
    expect(saved.content, note.content);
    expect(saved.displayText, note.content);
    expect(saved.caption, 'Separate caption needle260.');
    expect(saved.aiSourceText, contains('Original primary body.'));
    expect(saved.aiSourceText, contains('needle260'));
    expect(
      repo.search(const SearchFilters(query: 'needle260')).single.id,
      note.id,
    );
    repo.setCaption(note.id, '');
    expect(repo.getById(note.id)!.caption, isNull);
    expect(repo.getById(note.id)!.content, note.content);
    expect(repo.search(const SearchFilters(query: 'needle260')), isEmpty);
  });

  test(
    'nudge snapshot separates quiet from empty and keeps near reminders',
    () {
      expect(repo.nudgeSnapshot([]).hasData, isFalse);
      final near = create('Created long ago, due soon');
      final now = DateTime.now().toUtc();
      repo.setDueAt(near.id, now.add(const Duration(hours: 2)));
      repo.db.execute('UPDATE notes SET updated_at = ? WHERE id = ?', [
        now.subtract(const Duration(days: 90)).toIso8601String(),
        near.id,
      ]);
      for (var i = 0; i < 65; i++) {
        final stale = create('Old due $i');
        repo.setDueAt(stale.id, now.subtract(const Duration(days: 180)));
      }
      final repeat = create('Old series, still active');
      repo.setDueAt(
        repeat.id,
        now.subtract(const Duration(days: 180)),
        repeat: NoteRepeat.daily,
      );
      final snapshot = repo.nudgeSnapshot([]);
      expect(snapshot.hasData, isTrue);
      expect(
        snapshot.notes.map((n) => n.id),
        containsAll([near.id, repeat.id]),
      );
      expect(snapshot.notes, hasLength(2));
      repo.setAside(near.id);
      expect(
        repo.nudgeSnapshot([]).notes.map((n) => n.id),
        isNot(contains(near.id)),
      );
      repo.setDueAt(repeat.id, null);
      expect(repo.nudgeSnapshot([]).notes, isEmpty);
      expect(
        repo.nudgeSnapshot([]).hasData,
        isTrue,
        reason: 'no current work is not an empty library',
      );
      repo.db.execute('UPDATE notes SET deleted_at = ?', [
        DateTime.now().toUtc().toIso8601String(),
      ]);
      expect(repo.nudgeSnapshot([]).notes, isEmpty);
      expect(
        repo.nudgeSnapshot([]).hasData,
        isTrue,
        reason: 'retained trash is not a first-use library',
      );
    },
  );

  test('legacy type-check rebuild retains the new default urgency column', () {
    final path = '${root.path}/legacy.sqlite';
    final raw = sqlite3.open(path);
    raw.execute('''CREATE TABLE notes (
      id TEXT PRIMARY KEY NOT NULL,
      type TEXT NOT NULL CHECK (type IN ('text','voice','photo','file')),
      content TEXT, media_uri TEXT, media_hash TEXT, duration_ms INTEGER,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
      device_id TEXT NOT NULL, rev INTEGER NOT NULL, sync_state TEXT NOT NULL
    )''');
    raw.dispose();
    final legacy = NexDatabase.open(path);
    try {
      final migrated = SqliteNoteRepository(legacy, localDeviceId: 'test');
      final added = CaptureService(
        migrated,
        deviceId: 'test',
      ).submitTextCapture('Legacy upgraded')!;
      expect(added.isUrgent, isFalse);
      migrated.setUrgent(added.id, true);
      expect(migrated.getById(added.id)!.isUrgent, isTrue);
    } finally {
      legacy.close();
    }
  });
}
