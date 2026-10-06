import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A scheduled note does not exist until its time: not on the timeline, not
/// in search, not in the trash — and then it is an ordinary note.
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

  test('scheduled, the note is nowhere until its time', () {
    final note = capture.submitTextCapture('open this on new year')!;
    final tag = notes.upsertTag(name: 'future');
    notes.attachTag(noteId: note.id, tagId: tag.id);

    final held = scheduled.schedule(note.id, later)!;
    expect(held.content, 'open this on new year');
    expect(held.releaseAt, later);

    expect(notes.listTimeline(), isEmpty);
    expect(notes.search(const SearchFilters(query: 'year')), isEmpty);
    expect(notes.getById(note.id, includeDeleted: true), isNull);
    expect(
      LibraryMaintenance(notes).deletedNotes(),
      isEmpty,
      reason: 'not in the trash either',
    );
    expect(scheduled.pending().map((s) => s.id), [note.id]);

    expect(scheduled.releaseDue(now), isEmpty);
    expect(notes.listTimeline(), isEmpty);
  });

  test('at its time it arrives as an ordinary note, under the same id', () {
    final note = capture.submitTextCapture('a letter to myself')!;
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
    expect(notes.getById(c.id, includeDeleted: true), isNull);
    expect(scheduled.reschedule(c.id, later), isFalse);
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
}
