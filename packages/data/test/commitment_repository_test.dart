import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A commitment survives the round trip to SQLite with every field intact.
///
/// This exists for one unglamorous reason. The write is a hand-written
/// `INSERT OR REPLACE` with the column names in one string, the placeholders
/// in a second and the values in a third list — three places that have to
/// agree, none of which the compiler checks. Adding a field means editing all
/// three, and getting two of them right is the failure mode: too few
/// placeholders and every save throws, but a value landing one column to the
/// left is silent and writes the wrong data.
///
/// So this asserts the whole object rather than the field of the day, and it
/// asserts the ones that are easy to drop — the nullables, the booleans that
/// are stored as 0/1, and the times that go out as UTC and come back local.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteCommitmentRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_commitments_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteCommitmentRepository(db, localDeviceId: 'test-device');
  });

  tearDown(() {
    db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  NexCommitment full({bool notify = true}) => NexCommitment(
    id: 'c1',
    title: 'car insurance',
    cadence: NexCadence.years,
    every: 1,
    dueAt: DateTime(2030, 5, 10, 9, 30),
    lead: const Duration(days: 7),
    windowStart: 8 * 60,
    windowEnd: 22 * 60,
    lastMetAt: DateTime(2029, 5, 10, 9),
    metToday: 2,
    metTodayOn: '2029-05-10',
    paused: true,
    notify: notify,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 2, 2),
    rev: 4,
  );

  void expectSame(NexCommitment? read, NexCommitment written) {
    expect(read, isNotNull);
    final got = read!;
    expect(got.id, written.id);
    expect(got.title, written.title);
    expect(got.cadence, written.cadence);
    expect(got.every, written.every);
    expect(got.dueAt, written.dueAt);
    expect(got.lead, written.lead);
    expect(got.windowStart, written.windowStart);
    expect(got.windowEnd, written.windowEnd);
    expect(got.lastMetAt, written.lastMetAt);
    expect(got.metToday, written.metToday);
    expect(got.metTodayOn, written.metTodayOn);
    expect(got.paused, written.paused);
    expect(got.notify, written.notify);
    expect(got.createdAt, written.createdAt);
    expect(got.updatedAt, written.updatedAt);
    expect(got.rev, written.rev);
  }

  test('every field comes back the way it went in', () {
    final written = full();
    repo.save(written);
    expectSame(repo.getById('c1'), written);
  });

  test('the nullables come back null rather than as defaults', () {
    // The other half of the column alignment: a row of non-null values can
    // be shifted by one and still look plausible, but a null that arrives as
    // a number — or a number that arrives as null — cannot.
    final sparse = NexCommitment(
      id: 'c2',
      title: 'water',
      cadence: NexCadence.hours,
      every: 2,
      dueAt: DateTime(2030, 5, 10, 9),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    repo.save(sparse);
    final got = repo.getById('c2')!;
    expect(got.lead, isNull);
    expect(got.windowStart, isNull);
    expect(got.windowEnd, isNull);
    expect(got.lastMetAt, isNull);
    expect(got.metTodayOn, isNull);
    expect(got.metToday, 0);
    expect(got.paused, isFalse);
    // Not null, and not false: a commitment that was never told otherwise
    // rings. See [NexCommitment.notify].
    expect(got.notify, isTrue);
  });

  test('a silenced commitment stays silenced across a save', () {
    repo.save(full(notify: false));
    expect(repo.getById('c1')!.notify, isFalse);
    // And is not quietly re-armed by being written again.
    repo.save(repo.getById('c1')!);
    expect(repo.getById('c1')!.notify, isFalse);
  });

  test('a library created before the column reads as notifying', () {
    // The upgrade path, run for real rather than described. Every commitment
    // anybody set up in 1.11.0 lives in a database whose `commitments` table
    // has no `notify` column, and `CREATE TABLE IF NOT EXISTS` will not add
    // it — so the migration is the only thing standing between those people
    // and a feature that silently never fires for them.
    //
    // The table is put back into its 1.11.0 shape here, a row is written the
    // way that version wrote one, and the database is then *reopened*, which
    // is what runs the migration.
    final path = p.join(tmp.path, 'legacy.sqlite');
    final fresh = NexDatabase.open(path);
    fresh.db.execute('DROP TABLE commitments;');
    fresh.db.execute('''
CREATE TABLE commitments (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  cadence TEXT NOT NULL,
  every INTEGER NOT NULL,
  due_at TEXT NOT NULL,
  lead_seconds INTEGER,
  window_start INTEGER,
  window_end INTEGER,
  last_met_at TEXT,
  met_today INTEGER NOT NULL DEFAULT 0,
  met_today_on TEXT,
  paused INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  device_id TEXT NOT NULL DEFAULT '',
  rev INTEGER NOT NULL DEFAULT 1
);
''');
    fresh.db.execute(
      'INSERT INTO commitments (id, title, cadence, every, due_at, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'old',
        'rent',
        'months',
        1,
        '2030-05-10T09:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
      ],
    );
    fresh.close();

    final upgraded = NexDatabase.open(path);
    addTearDown(upgraded.close);
    final got = SqliteCommitmentRepository(upgraded).getById('old')!;
    expect(got.title, 'rent');
    expect(got.notify, isTrue);
  });

  test('a saved commitment is in the list, and a deleted one is not', () {
    repo.save(full());
    expect(repo.list().map((c) => c.id), ['c1']);
    repo.delete('c1');
    expect(repo.list(), isEmpty);
    expect(repo.getById('c1'), isNull);
  });
}
