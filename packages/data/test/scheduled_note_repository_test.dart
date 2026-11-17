import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A scheduled note does not surface until its time: not on the timeline,
/// not in search, not in the trash — and then it is an ordinary note.
///
/// The note row itself never leaves the library: waiting is an arrangement of
/// a live row, the way set-aside is. What these tests pin is that the
/// arrangement holds against exactly the things that used to break it — a
/// sync pull resurrecting the deleted row, a trash purge eating the waiting
/// copy, a release that arrives anywhere but the outbox.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository notes;
  late CaptureService capture;
  late SqliteScheduledNoteRepository scheduled;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_scheduled_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    notes = SqliteNoteRepository(db, localDeviceId: 'd');
    capture = CaptureService(notes, deviceId: 'd');
    scheduled = SqliteScheduledNoteRepository(db, notes);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  final now = DateTime.utc(2026, 10, 5, 12);
  final later = DateTime.utc(2027, 1, 1, 9);

  test('scheduled, the note is in no view until its time', () {
    final note = capture.submitTextCapture('open this on new year')!;
    final tag = notes.upsertTag(name: 'future');
    notes.attachTag(noteId: note.id, tagId: tag.id);

    final held = scheduled.schedule(note.id, later)!;
    expect(held.content, 'open this on new year');
    expect(held.releaseAt, later);

    expect(notes.listTimeline(), isEmpty);
    expect(notes.search(const SearchFilters(query: 'year')), isEmpty);
    // The row stays — hidden from every view, still in the library, still in
    // every backup, which is the whole point of the waiting being a
    // arrangement of it rather than its removal.
    expect(
      notes.getById(note.id, includeDeleted: true)?.content,
      'open this on new year',
    );
    expect(
      notes.getById(note.id),
      isNotNull,
      reason: 'readable by id, hidden from views',
    );
    expect(
      LibraryMaintenance(notes).deletedNotes(),
      isEmpty,
      reason: 'not in the trash either',
    );
    expect(scheduled.pending().map((s) => s.id), [note.id]);

    expect(scheduled.releaseDue(now), isEmpty);
    expect(notes.listTimeline(), isEmpty);
  });

  test('waiting, it is found by meaning no more than by its words, and its '
      'tags do not count on Home (2.8.1)', () {
    final note = capture.submitTextCapture('a dentist on new year')!;
    final other = capture.submitTextCapture('teeth cleaning')!;
    notes.setEmbedding(note.id, [1, 0, 0]);
    notes.setEmbedding(other.id, [0.9, 0.1, 0]);
    final tag = notes.upsertTag(name: 'health');
    notes.attachTag(noteId: note.id, tagId: tag.id);
    expect(
      notes.nearestEmbeddings([1, 0, 0]).map((e) => e.noteId),
      contains(note.id),
    );

    scheduled.schedule(note.id, later);

    expect(notes.nearestEmbeddings([1, 0, 0]).map((e) => e.noteId), [other.id]);
    final usage = LibraryMaintenance(notes).tagUsage(timelineOnly: true);
    expect(usage.singleWhere((u) => u.tag.id == tag.id).count, 0);
  });

  test('the title and tags waiting with a note come back with it', () {
    final note = capture.submitTextCapture('a note with a heading')!;
    notes.setTitle(note.id, 'The heading');
    final tag = notes.upsertTag(name: 'future');
    notes.attachTag(noteId: note.id, tagId: tag.id);

    expect(scheduled.schedule(note.id, later), isNotNull);
    expect(notes.getById(note.id), isNotNull);

    final arrived = scheduled
        .releaseDue(later.add(const Duration(hours: 1)))
        .single;
    expect(arrived.content, 'a note with a heading');
    expect(arrived.title, 'The heading');
    expect(arrived.tags.map((t) => t.name), ['future']);
    // The heading is searchable again too, not only present on the card.
    expect(
      notes.search(const SearchFilters(query: 'heading')).single.id,
      note.id,
    );
  });

  test('a note with attachments is not scheduled away from them', () {
    final note = capture.submitTextCapture('a note with a document')!;
    final document = File(p.join(tmp.path, 'document.pdf'))
      ..writeAsBytesSync([1, 2, 3]);
    SqliteAttachmentRepository(notes, localDeviceId: 'd').add(
      note.id,
      kind: AttachmentKind.file,
      mediaUri: document.path,
      mediaHash: 'hash',
    );

    expect(scheduled.schedule(note.id, later), isNull);
    expect(notes.getById(note.id)?.attachmentCount, 1);
    expect(document.existsSync(), isTrue);
  });

  test('at its time it arrives as an ordinary note, under the same id', () {
    final note = capture.submitTextCapture('a letter to myself')!;
    final before = notes.getById(note.id)!.rev;
    scheduled.schedule(note.id, later);

    final arrived = scheduled.releaseDue(later.add(const Duration(hours: 3)));
    expect(arrived.single.id, note.id);
    expect(arrived.single.content, 'a letter to myself');
    // Filed at its delivery time, not when the app happened to look.
    expect(arrived.single.createdAt, later);
    expect(notes.listTimeline().single.id, note.id);
    expect(
      notes.search(const SearchFilters(query: 'letter')).single.id,
      note.id,
    );
    expect(scheduled.pending(), isEmpty);
    expect(scheduled.releaseDue(later.add(const Duration(days: 1))), isEmpty);
    // The arrival is an edit: a higher revision, in the outbox, so the day
    // it lands under travels with it.
    expect(arrived.single.rev, greaterThan(before));
    expect(
      notes.listPending(includeDeleted: true).map((n) => n.id),
      contains(note.id),
    );
  });

  test('only what is due arrives, the earliest first', () {
    final a = capture.submitTextCapture('first')!;
    final b = capture.submitTextCapture('second')!;
    final c = capture.submitTextCapture('third')!;
    scheduled.schedule(b.id, DateTime.utc(2026, 11, 2));
    scheduled.schedule(a.id, DateTime.utc(2026, 11, 1));
    scheduled.schedule(c.id, DateTime.utc(2027, 3, 1));

    final arrived = scheduled.releaseDue(DateTime.utc(2026, 12, 1));
    expect(arrived.map((n) => n.content), ['first', 'second']);
    expect(scheduled.pending().single.id, c.id);
  });

  test('send now, a new time, or throw it away', () {
    final a = capture.submitTextCapture('now please')!;
    final b = capture.submitTextCapture('a bit later')!;
    final c = capture.submitTextCapture('never mind')!;
    for (final n in [a, b, c]) {
      scheduled.schedule(n.id, later);
    }

    expect(scheduled.releaseNow(a.id, now)!.createdAt, now);
    expect(scheduled.releaseNow(a.id, now), isNull);

    final sooner = DateTime.utc(2026, 10, 6);
    expect(scheduled.reschedule(b.id, sooner), isTrue);
    expect(scheduled.pending().first.releaseAt, sooner);

    scheduled.discard(c.id);
    expect(scheduled.pending().map((s) => s.id), [b.id]);
    // Discarded like any live note is deleted: in the trash, restorable —
    // not gone without a trace the way the old hard delete took it.
    expect(notes.getById(c.id), isNull);
    final maintenance = LibraryMaintenance(notes);
    expect(maintenance.deletedNotes().map((n) => n.id), [c.id]);
    expect(scheduled.reschedule(c.id, later), isFalse);
  });

  test('a discarded waiting note comes back from the trash intact', () {
    final note = capture.submitTextCapture('changed my mind')!;
    scheduled.schedule(note.id, later);
    scheduled.discard(note.id);

    notes.undelete(note.id);
    final back = notes.getById(note.id);
    expect(back?.content, 'changed my mind');
    expect(notes.listTimeline().map((n) => n.id), [
      note.id,
    ], reason: 'undeleted straight back onto the timeline');
    expect(
      scheduled.pending(),
      isEmpty,
      reason: 'the wait ended when it was discarded',
    );
  });

  test('only a live text note with words can be scheduled', () {
    final empty = capture.submitTextCapture(' ');
    if (empty != null) {
      expect(scheduled.schedule(empty.id, later), isNull);
    }
    final gone = capture.submitTextCapture('deleted already')!;
    notes.softDelete(gone.id);
    expect(scheduled.schedule(gone.id, later), isNull);
    expect(scheduled.schedule('no-such-note', later), isNull);
  });

  test('a scheduled note survives closing and reopening the library', () {
    final note = capture.submitTextCapture('kept on disk')!;
    scheduled.schedule(note.id, later);
    db.close();
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    notes = SqliteNoteRepository(db, localDeviceId: 'd');
    scheduled = SqliteScheduledNoteRepository(db, notes);
    expect(scheduled.pending().single.content, 'kept on disk');
  });

  test('waiting is a local arrangement: it never enters the outbox', () {
    final note = capture.submitTextCapture('not synced yet')!;
    // A clean, fully synced row — the state a paired device's note is in by
    // the time anyone schedules it.
    final settled = notes.getById(note.id)!.rev;
    notes.markSynced(note.id, serverRev: settled);

    scheduled.schedule(note.id, later);

    expect(
      notes.listPending(includeDeleted: true),
      isEmpty,
      reason: 'hiding a note on this device is not a change any peer needs',
    );
    expect(
      notes.getById(note.id, includeDeleted: true)!.rev,
      settled,
      reason: 'the revision stands still for an arrangement',
    );
  });

  test('a peer pull while waiting cannot surface the note early', () {
    // The resurrection this pins: the old design deleted the row outright,
    // so the next sync pull — an auto-cycle runs every fifteen minutes —
    // re-inserted the note it could still see, and the "hidden until its
    // time" promise lasted exactly one sync cycle.
    final note = capture.submitTextCapture('hidden from peers too')!;
    scheduled.schedule(note.id, later);

    // The server still holds its copy of the row, exactly as it was.
    notes.applyRemoteNote(
      id: note.id,
      type: NoteType.text,
      content: 'hidden from peers too',
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      deviceId: 'peer',
      rev: 1,
      tagIds: const [],
    );

    expect(
      notes.listTimeline(),
      isEmpty,
      reason: 'the pulled copy keeps waiting like the row it landed on',
    );
    expect(scheduled.pending().map((s) => s.id), [note.id]);

    final arrived = scheduled.releaseDue(later).single;
    expect(arrived.content, 'hidden from peers too');
  });

  test('discarded, the trash sweep takes it for good', () {
    final note = capture.submitTextCapture('throw it away')!;
    scheduled.schedule(
      note.id,
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    scheduled.discard(note.id);

    final maintenance = LibraryMaintenance(notes);
    expect(maintenance.deletedNotes().map((n) => n.id), [note.id]);

    // Beyond any tombstone the sweep could be given, and beyond this note's.
    maintenance.purgeDeletedBefore(
      DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    expect(notes.getById(note.id, includeDeleted: true), isNull);
    expect(scheduled.pending(), isEmpty);
  });
}
