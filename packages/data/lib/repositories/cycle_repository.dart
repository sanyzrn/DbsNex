import 'package:nex_core/nex_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../schema/database.dart';
import '../schema/write_lock.dart';

/// Storage for «Cycle»: periods and what was noted about each day.
///
/// Synchronous, like every repository here; it runs inside the database
/// worker's isolate.
class SqliteCycleRepository {
  SqliteCycleRepository(this._db);

  final NexDatabase _db;

  Database get db => _db.db;

  /// Every period, the earliest first.
  List<CyclePeriod> periods() => [
    for (final row in db.select(
      'SELECT * FROM cycle_periods ORDER BY start_day, id',
    ))
      _period(row),
  ];

  /// Starts a period on [day].
  ///
  /// A day already inside a period is that period — tapping "started" twice
  /// does not make two — and so is a day a few after an open one began, which
  /// is the same period noticed late. An open period older than that is
  /// closed first at its expected length, so starting a new one never leaves
  /// a forgotten one running.
  CyclePeriod startPeriod(
    DateTime day, {
    int closeAfter = 5,
  }) => db.together(() {
    final date = CycleDate.of(day);
    final all = periods();
    for (final p in all) {
      if (p.contains(date) && (!p.isOpen || date.daysSince(p.start) < 10)) {
        return p;
      }
    }
    for (final p in all.where((p) => p.isOpen)) {
      final end = p.start.addDays(closeAfter - 1);
      _setEnd(p.id, end.isBefore(date) ? end : date.addDays(-1));
    }
    final period = CyclePeriod(id: newUuidV7(), start: date);
    db.execute(
      'INSERT INTO cycle_periods (id, start_day, end_day) VALUES (?, ?, NULL)',
      [period.id, '${period.start}'],
    );
    return period;
  });

  /// Ends [id] on [day], which is clamped to no earlier than its start.
  void endPeriod(String id, DateTime day) {
    final rows = db.select('SELECT * FROM cycle_periods WHERE id = ?', [id]);
    if (rows.isEmpty) return;
    final period = _period(rows.first);
    final date = CycleDate.of(day);
    _setEnd(id, date.isBefore(period.start) ? period.start : date);
  }

  /// Moves [id] to [start]..[end] (end null: still going).
  void updatePeriod(String id, DateTime start, DateTime? end) {
    final s = CycleDate.of(start);
    final e = end == null ? null : CycleDate.of(end);
    db.execute(
      'UPDATE cycle_periods SET start_day = ?, end_day = ? WHERE id = ?',
      ['$s', e == null ? null : '${e.isBefore(s) ? s : e}', id],
    );
  }

  void deletePeriod(String id) =>
      db.execute('DELETE FROM cycle_periods WHERE id = ?', [id]);

  /// What was noted about [day], or null.
  CycleDayLog? day(DateTime day) {
    final rows = db.select('SELECT * FROM cycle_days WHERE day = ?', [
      '${CycleDate.of(day)}',
    ]);
    return rows.isEmpty ? null : _log(rows.first);
  }

  /// Every logged day from [from] to [to], inclusive.
  List<CycleDayLog> days(DateTime from, DateTime to) => [
    for (final row in db.select(
      'SELECT * FROM cycle_days WHERE day BETWEEN ? AND ? ORDER BY day',
      ['${CycleDate.of(from)}', '${CycleDate.of(to)}'],
    ))
      _log(row),
  ];

  /// Saves [log], or forgets the day when nothing is left on it.
  void saveDay(CycleDayLog log) {
    if (log.isEmpty) {
      db.execute('DELETE FROM cycle_days WHERE day = ?', ['${log.day}']);
      return;
    }
    db.execute(
      '''
INSERT OR REPLACE INTO cycle_days
  (day, flow, symptoms, mood, energy, pain_relief, intimacy, pill, note,
   temperature, ovulation_test, mucus)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        '${log.day}',
        log.flow?.name,
        log.symptoms.isEmpty
            ? null
            : (log.symptoms.map((s) => s.name).toList()..sort()).join(','),
        log.mood?.name,
        log.energy,
        log.painRelief ? 1 : 0,
        log.intimacy ? 1 : 0,
        log.pill ? 1 : 0,
        log.note?.trim().isEmpty ?? true ? null : log.note!.trim(),
        log.temperature,
        log.ovulationTest?.name,
        log.mucus?.name,
      ],
    );
  }

  /// Every period and every logged day, gone. Nothing else is touched.
  void deleteAll() => db.together(() {
    db.execute('DELETE FROM cycle_periods');
    db.execute('DELETE FROM cycle_days');
  });

  void _setEnd(String id, CycleDate end) => db.execute(
    'UPDATE cycle_periods SET end_day = ? WHERE id = ?',
    ['$end', id],
  );

  static CyclePeriod _period(Row row) => CyclePeriod(
    id: row['id'] as String,
    start: CycleDate.parse(row['start_day'] as String),
    end: row['end_day'] == null
        ? null
        : CycleDate.parse(row['end_day'] as String),
  );

  static CycleDayLog _log(Row row) => CycleDayLog(
    day: CycleDate.parse(row['day'] as String),
    flow: CycleFlow.fromWire(row['flow'] as String?),
    symptoms: CycleSymptom.parse(row['symptoms'] as String?),
    mood: CycleMood.fromWire(row['mood'] as String?),
    energy: row['energy'] as int?,
    painRelief: row['pain_relief'] == 1,
    intimacy: row['intimacy'] == 1,
    pill: row['pill'] == 1,
    note: row['note'] as String?,
    temperature: (row['temperature'] as num?)?.toDouble(),
    ovulationTest: CycleOvulationTest.fromWire(
      row['ovulation_test'] as String?,
    ),
    mucus: CycleMucus.fromWire(row['mucus'] as String?),
  );
}
