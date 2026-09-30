import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Threads are views over notes (W5.3): joining, leaving or deleting one
/// never changes a note, and the app only suggests one when it is clear.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository notes;
  late CaptureService capture;
  late SqliteThreadRepository threads;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_threads_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    notes = SqliteNoteRepository(db, localDeviceId: 'd');
    capture = CaptureService(notes, deviceId: 'd');
    threads = SqliteThreadRepository(db, notes, localDeviceId: 'd');
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note text(String content) => capture.submitTextCapture(content)!;

  test('a thread is a view: its notes stay on the timeline', () {
    final a = text('kitchen renovation: measure the cabinets');
    final b = text('kitchen renovation: order the tiles');
    final thread = threads.create('Kitchen', noteIds: [a.id, b.id]);

    expect(thread.noteCount, 2);
    expect(threads.notes(thread.id).map((n) => n.id), [a.id, b.id]);
    expect(threads.forNote(a.id).single.name, 'Kitchen');
    expect(notes.listTimeline().map((n) => n.id), containsAll([a.id, b.id]));

    threads.remove(thread.id, a.id);
    expect(threads.notes(thread.id).map((n) => n.id), [b.id]);
    expect(notes.getById(a.id), isNotNull);

    threads.delete(thread.id);
    expect(threads.list(), isEmpty);
    expect(threads.forNote(b.id), isEmpty);
    expect(
      notes.getById(b.id),
      isNotNull,
      reason: 'deleting a thread keeps notes',
    );
  });

  test('a deleted note leaves the thread view and its count', () {
    final a = text('garden plan: plant tomatoes along the fence');
    final b = text('garden plan: buy compost for the tomatoes');
    final thread = threads.create('Garden', noteIds: [a.id, b.id]);
    notes.softDelete(a.id);
    expect(threads.notes(thread.id).map((n) => n.id), [b.id]);
    expect(threads.list().single.noteCount, 1);
  });

  test('a new note that continues a thread is offered to it', () {
    final a = text('Kitchen renovation: cabinets measured, tiles ordered');
    final thread = threads.create('Kitchen', noteIds: [a.id]);
    final next = text('Kitchen renovation: tiles arrived, cabinets next week');

    final suggestion = threads.suggest(next.id);
    expect(suggestion?.joins, isTrue);
    expect(suggestion?.thread?.id, thread.id);

    // Once it is in, the same thread is not offered again.
    threads.add(thread.id, next.id);
    expect(threads.suggest(next.id), isNull);
  });

  test('two clearly related notes can start a thread', () {
    final a = text('Trip to Shiraz: book the hotel near Eram garden');
    final b = text('Trip to Shiraz: hotel booked, Eram garden on Friday');
    final suggestion = threads.suggest(b.id);
    expect(suggestion?.joins, isFalse);
    expect(suggestion?.withNoteId, a.id);
    expect(suggestion?.name, isNotEmpty);
  });

  test('unrelated notes suggest nothing', () {
    text('Buy milk and bread');
    text('Call the dentist about Tuesday');
    final c = text('The quarterly report is due at the end of the month');
    expect(threads.suggest(c.id), isNull);
  });

  test('links to the same site belong together', () {
    final a = capture.submitLinkCapture('https://github.com/sanyzrn/nex')!;
    threads.create('Nex', noteIds: [a.id]);
    final b = capture.submitLinkCapture('https://github.com/sanyzrn/other')!;
    expect(threads.suggest(b.id)?.thread?.name, 'Nex');
  });

  test('Persian words count as words', () {
    final a = text(
      'بازسازی آشپزخانه: کابینت‌ها اندازه‌گیری شد و کاشی سفارش دادم',
    );
    threads.create('آشپزخانه', noteIds: [a.id]);
    final b = text('بازسازی آشپزخانه: کاشی رسید، کابینت‌ها هفته بعد');
    expect(threads.suggest(b.id)?.thread?.name, 'آشپزخانه');
  });
}
