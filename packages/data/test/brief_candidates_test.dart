import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `listBriefCandidates` is the brief's answer to a windowed timeline: the
/// set is read from the library itself — everything that can be waiting,
/// with no count cap, plus the newest ordinary prose — rather than from
/// whatever recency slice the timeline happens to have loaded. What is
/// tested here is that coverage, the ordering, and the timeline's own rules
/// about what counts as gone.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_brief_candidates_');
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
    NoteType type = NoteType.text,
  }) => repo.insert(
    Note(
      id: id,
      type: type,
      content: content,
      createdAt: at ?? DateTime.utc(2026, 1, 1),
      updatedAt: at ?? DateTime.utc(2026, 1, 1),
      deviceId: 'test-device',
      rev: 1,
      syncState: SyncState.pending,
      isUrgent: urgent,
    ),
  );

  test('reminders, urgent notes and checklists, however old', () {
    final dated = capture('dated', 'the appointment');
    capture('urgent', 'call the supplier', urgent: true);
    capture('list', '- [ ] milk\n- [ ] bread', type: NoteType.checklist);
    repo.setDueAt(dated.id, DateTime.now().add(const Duration(days: 1)));

    final candidates = repo.listBriefCandidates();

    // All three were written months ago; what is on them, not when they
    // were touched, is what puts them in the set.
    expect(
      candidates.map((note) => note.id),
      containsAll(['dated', 'urgent', 'list']),
    );
  });

  test(
    'recent ordinary prose is in reach; the older pool is the newest 200',
    () {
      final now = DateTime.now();
      capture('today', 'written this morning', at: now);
      // Older than the recent window, so only the bounded pool can carry
      // them: the newest two hundred, and not the fifty behind them.
      for (var i = 0; i < 250; i++) {
        capture(
          'ordinary$i',
          'thought $i',
          at: now.subtract(Duration(days: 8 + i)),
        );
      }

      final candidates = repo.listBriefCandidates();
      final ids = candidates.map((note) => note.id).toList();

      expect(ids, contains('today'));
      // The pool is the newest two hundred notes overall; this morning's
      // note holds one of those places, so 199 of the older ones ride along.
      expect(ids.where((id) => id.startsWith('ordinary')), hasLength(199));
      expect(ids, contains('ordinary198'));
      expect(ids, isNot(contains('ordinary199')));
      expect(ids.indexOf('ordinary0'), lessThan(ids.indexOf('ordinary198')));
    },
  );

  test('urgent first, then dated soonest first, then newest', () {
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

    expect(repo.listBriefCandidates().map((note) => note.id), [
      'newer-urgent',
      'older-urgent',
      'sooner',
      'later',
    ]);
  });

  test('a deleted note or one set aside is not a candidate', () {
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

    expect(repo.listBriefCandidates(), isEmpty);
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
    expect(repo.listBriefCandidates().map((note) => note.id), ['returned']);
  });

  test('a note that has not arrived yet is not a candidate', () {
    final waiting = capture('waiting', 'filed under its own time');
    repo.setDueAt(waiting.id, DateTime.now().add(const Duration(days: 1)));
    db.db.execute('UPDATE notes SET scheduled_until = ? WHERE id = ?', [
      DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
      waiting.id,
    ]);

    expect(repo.listBriefCandidates(), isEmpty);
  });

  test('no cap: an urgent note survives more than 200 dated reminders', () {
    // The old query cut at two hundred rows, and "urgent first" only
    // protected the urgent ones from the cut. The candidate set has no
    // count cap on what can be waiting: every reminder is in it.
    capture('priority', 'please do this', urgent: true);
    for (var i = 0; i < 205; i++) {
      final dated = capture('dated$i', 'appointment $i');
      repo.setDueAt(dated.id, DateTime.now().add(Duration(days: i + 1)));
    }
    final candidates = repo.listBriefCandidates();
    expect(candidates, hasLength(206));
    expect(candidates.first.id, 'priority');
    expect(candidates.map((note) => note.id), contains('dated204'));
  });
}
