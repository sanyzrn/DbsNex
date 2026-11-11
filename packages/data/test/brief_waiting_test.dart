import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `listBriefWaiting` is the brief's answer to a windowed timeline: the notes
/// chosen by what is on them — a reminder, an urgent mark — rather than by
/// when they were last touched. What is tested here is that it returns
/// exactly those, under the timeline's own rules about what counts as gone.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_brief_waiting_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note capture(
    String id,
    String content, {
    DateTime? at,
    bool urgent = false,
  }) => repo.insert(
    Note(
      id: id,
      type: NoteType.text,
      content: content,
      createdAt: at ?? DateTime.utc(2026, 1, 1),
      updatedAt: at ?? DateTime.utc(2026, 1, 1),
      deviceId: 'test-device',
      rev: 1,
      syncState: SyncState.pending,
      isUrgent: urgent,
    ),
  );

  test('reminders and urgent notes, and nobody else', () {
    final plain = capture('plain', 'written this morning');
    final dated = capture(
      'dated',
      'the appointment',
      at: DateTime.utc(2026, 1),
    );
    capture('urgent', 'call the supplier', urgent: true);
    repo.setDueAt(dated.id, DateTime.now().add(const Duration(days: 1)));

    final waiting = repo.listBriefWaiting();

    expect(waiting.map((note) => note.id), containsAll(['dated', 'urgent']));
    expect(waiting.map((note) => note.id), isNot(contains(plain.id)));
  });

  test('urgent first, then dated soonest first', () {
    final later = capture('later', 'due next week');
    final sooner = capture('sooner', 'due tomorrow');
    capture(
      'older-urgent',
      'urgent, older',
      at: DateTime.utc(2026, 1, 1),
      urgent: true,
    );
    capture(
      'newer-urgent',
      'urgent, newer',
      at: DateTime.utc(2026, 6, 1),
      urgent: true,
    );
    final now = DateTime.now();
    repo.setDueAt(later.id, now.add(const Duration(days: 7)));
    repo.setDueAt(sooner.id, now.add(const Duration(days: 1)));

    expect(repo.listBriefWaiting().map((note) => note.id), [
      'newer-urgent',
      'older-urgent',
      'sooner',
      'later',
    ]);
  });

  test('a deleted note or one set aside is not waiting', () {
    final deleted = capture('deleted', 'thrown away');
    final setAside = capture('aside', 'put to one side');
    repo.setDueAt(deleted.id, DateTime.now().add(const Duration(days: 1)));
    repo.setDueAt(setAside.id, DateTime.now().add(const Duration(days: 1)));
    repo.softDelete(deleted.id);
    expect(
      repo.setAside(
        setAside.id,
        until: DateTime.now().add(const Duration(days: 30)),
      ),
      isTrue,
    );

    expect(repo.listBriefWaiting(), isEmpty);
  });

  test('a set-aside note whose return time has passed is back', () {
    final returned = capture('returned', 'back on the timeline');
    repo.setDueAt(returned.id, DateTime.now().add(const Duration(days: 1)));
    expect(
      repo.setAside(
        returned.id,
        until: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
      isFalse,
      reason: 'a return time in the past is not a set-aside at all',
    );
    expect(repo.listBriefWaiting().map((note) => note.id), ['returned']);
  });

  test('the limit keeps the front of each group', () {
    final urgent = capture('urgent', 'urgent, no date', urgent: true);
    for (var i = 0; i < 3; i++) {
      final dated = capture('dated$i', 'due soon $i');
      repo.setDueAt(dated.id, DateTime.now().add(Duration(days: i + 1)));
    }

    final waiting = repo.listBriefWaiting(limit: 2);

    expect(waiting.map((note) => note.id), ['urgent', 'dated0']);
    expect(waiting.map((note) => note.id), contains(urgent.id));
  });

  test('an urgent note survives more than 200 dated reminders', () {
    final urgent = capture('priority', 'please do this', urgent: true);
    for (var i = 0; i < 205; i++) {
      final dated = capture('dated$i', 'appointment $i');
      repo.setDueAt(dated.id, DateTime.now().add(Duration(days: i + 1)));
    }
    final waiting = repo.listBriefWaiting(limit: 200);
    expect(waiting, hasLength(200));
    expect(waiting.first.id, urgent.id);
  });
}
