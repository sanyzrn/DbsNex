import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A library written by the 2.3.6 code itself — the last version in the
/// stores before 2.8.3 — opened by this one (2.8.3).
///
/// The fixture was made by running 2.3.6's own repositories (schema 1) and
/// is never regenerated: it is what people's phones actually hold. Opening
/// it must keep every note, kind, tag, thread, attachment, reminder, aside,
/// deleted note, recurring item and module record, find them again by
/// their words, and let new writes land.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_upgrade_236_');
    final path = p.join(tmp.path, 'nex.sqlite');
    File(p.join('test', 'fixtures', 'library_2_3_6.sqlite')).copySync(path);
    db = NexDatabase.open(path);
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test('the library is brought to the current layout', () {
    expect(
      db.db.select('PRAGMA user_version').first.values.first,
      NexDatabase.schemaVersion,
    );
    expect(db.db.select('PRAGMA integrity_check').first.values.first, 'ok');
  });

  test('every note is there, as it was', () {
    final timeline = repo.listTimeline(limit: 100);
    final byContent = {for (final n in timeline) n.content ?? n.type.name: n};
    expect(byContent.keys, contains('سلام دنیا، یادداشت فارسی قدیمی'));
    expect(byContent.keys, contains('Old English note about the boiler'));
    expect(timeline.map((n) => n.type).toSet(), {
      NoteType.text,
      NoteType.checklist,
      NoteType.link,
      NoteType.voice,
      NoteType.photo,
      NoteType.file,
    });
    // Deleted stays deleted; set aside stays aside.
    expect(byContent.keys, isNot(contains('deleted one')));
    expect(byContent.keys, isNot(contains('set aside note')));
    expect(repo.listSetAside().map((n) => n.content), ['set aside note']);

    final check = timeline.firstWhere((n) => n.type == NoteType.checklist);
    expect(check.content, '- [x] شیر\n- [ ] نان\n- [ ] Eggs');
    final link = timeline.firstWhere((n) => n.type == NoteType.link);
    expect(link.title, 'A video');
    expect(link.linkExcerpt, 'An excerpt');
    final voice = timeline.firstWhere((n) => n.type == NoteType.voice);
    expect(voice.transcriptText, 'متن صدای ضبط شده');
    expect(voice.mediaUri, '/data/media/v.m4a');
    final photo = timeline.firstWhere((n) => n.type == NoteType.photo);
    expect(photo.ocrText, 'receipt total 120000');
    expect(photo.caption, 'رسید خرید');
    final reminder = byContent['Old English note about the boiler']!;
    expect(reminder.dueAt, DateTime.utc(2026, 12, 1, 6));
  });

  test('tags, threads and attachments are kept', () {
    final tags = repo.listTags();
    final work = tags.firstWhere((t) => t.name == 'کار');
    final tagged = repo.listTimeline(limit: 100, tagId: work.id);
    expect(tagged, hasLength(2));
    final threads = SqliteThreadRepository(
      db,
      repo,
      localDeviceId: 'new-device',
    ).list();
    expect(threads.map((t) => t.name), ['رشته']);
    final persian = tagged.firstWhere((n) => n.type == NoteType.text);
    final attachments = SqliteAttachmentRepository(
      repo,
      localDeviceId: 'new-device',
    ).forNote(persian.id);
    expect(attachments.single.mediaUri, '/data/media/a.jpg');
  });

  test('old notes are found by their words, Persian and English', () {
    expect(
      repo.search(const SearchFilters(query: 'فارسی')).map((n) => n.content),
      contains('سلام دنیا، یادداشت فارسی قدیمی'),
    );
    expect(repo.search(const SearchFilters(query: 'boiler')), hasLength(1));
    // Words that live on a photo and in a recording, not in the content.
    expect(repo.search(const SearchFilters(query: 'receipt')), hasLength(1));
    expect(repo.search(const SearchFilters(query: 'ضبط')), hasLength(1));
  });

  test('recurring items and module records are kept', () {
    final commitments = SqliteCommitmentRepository(
      db,
      localDeviceId: 'new-device',
    ).list();
    expect(commitments.single.title, 'قبض برق');
    expect(commitments.single.every, 30);
    final habits = SqliteModuleRecordRepository(db).list('habits', 'habit');
    expect(habits.single.body['name'], 'ورزش');
  });

  test('new notes land and old ones can be edited', () {
    final now = DateTime.now().toUtc();
    final added = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'written after the update',
        createdAt: now,
        updatedAt: now,
        deviceId: 'new-device',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    expect(repo.getById(added.id)?.content, 'written after the update');
    final old = repo
        .listTimeline(limit: 100)
        .firstWhere((n) => n.content == 'Old English note about the boiler');
    repo.updateContent(old.id, 'Old note, edited after the update');
    expect(repo.search(const SearchFilters(query: 'edited')).single.id, old.id);
  });
}
