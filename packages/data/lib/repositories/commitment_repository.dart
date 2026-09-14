import 'package:nex_core/nex_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../schema/database.dart';

/// SQLite storage for the recurring obligations — see [NexCommitment] in
/// packages/core for why they are their own thing rather than notes.
///
/// Synchronous throughout, like every other repository here: `package:sqlite3`
/// is a synchronous FFI binding and the whole store runs inside the database
/// worker's isolate.
///
/// Dates are stored as UTC ISO strings, the same as everywhere else in this
/// schema, and handed back as **local** times. That conversion is not
/// incidental: a commitment's due time is an hour in somebody's own day — the
/// first of the month, eight in the morning — and every screen, every brief
/// line and every piece of arithmetic in `commitment.dart` works in local
/// time. Storing UTC keeps the file portable between devices; converting on
/// the way out keeps the meaning.
class SqliteCommitmentRepository {
  SqliteCommitmentRepository(this._db, {this.localDeviceId});

  final NexDatabase _db;

  /// Stamped as `device_id` on every local write, so the rows are ready for
  /// the sync machinery whenever it reaches them. Null until then, the same
  /// as [SqliteNoteRepository.localDeviceId].
  final String? localDeviceId;

  Database get db => _db.db;

  /// Every live commitment, soonest first.
  ///
  /// Soonest first rather than newest: this list is read to answer "what is
  /// coming", by the screen and by the brief alike, and creation order is not
  /// something anybody wants to think in.
  List<NexCommitment> list() {
    final rows = db.select(
      'SELECT * FROM commitments WHERE deleted_at IS NULL ORDER BY due_at ASC',
    );
    return [for (final row in rows) _fromRow(row)];
  }

  NexCommitment? getById(String id) {
    final rows = db.select(
      'SELECT * FROM commitments WHERE id = ? AND deleted_at IS NULL',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Writes [commitment], inserting or replacing by id.
  ///
  /// One method rather than insert and update, because every caller here
  /// holds a whole immutable [NexCommitment] and there is no partial write to
  /// express. `INSERT OR REPLACE` on a primary key is the honest spelling of
  /// that, and it makes the save path the same whether the editor was opened
  /// on a new commitment or an existing one.
  NexCommitment save(NexCommitment commitment) {
    db.execute(
      '''
INSERT OR REPLACE INTO commitments (
  id, title, cadence, every, due_at, lead_seconds,
  window_start, window_end, last_met_at, met_today, met_today_on,
  paused, notify, created_at, updated_at, deleted_at, device_id, rev
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
''',
      [
        commitment.id,
        commitment.title,
        commitment.cadence.wireName,
        commitment.every,
        commitment.dueAt.toUtc().toIso8601String(),
        commitment.lead?.inSeconds,
        commitment.windowStart,
        commitment.windowEnd,
        commitment.lastMetAt?.toUtc().toIso8601String(),
        commitment.metToday,
        commitment.metTodayOn,
        commitment.paused ? 1 : 0,
        commitment.notify ? 1 : 0,
        commitment.createdAt.toUtc().toIso8601String(),
        commitment.updatedAt.toUtc().toIso8601String(),
        localDeviceId ?? '',
        commitment.rev,
      ],
    );
    return commitment;
  }

  /// Marks it met at [at] and rolls it forward to its next turn.
  ///
  /// Read, advance, write — rather than arithmetic in SQL — because the
  /// arithmetic is the hard part and it lives in core where it is tested
  /// without a database. Months do not have a fixed length, an hourly
  /// commitment has to land inside its waking window, and a date missed for
  /// three weeks has to come back into the future. None of that belongs in a
  /// SQL expression.
  NexCommitment? markMet(String id, {DateTime? at}) {
    final current = getById(id);
    if (current == null) return null;
    return save(current.met(at ?? DateTime.now()));
  }

  /// Soft-deletes, the way a note is deleted.
  ///
  /// Soft rather than hard, so the row is still there for a later sync to
  /// carry the deletion rather than the row silently reappearing from another
  /// device — the same reasoning `notes` follows (ADR-006). Nothing in the
  /// app surfaces deleted commitments; Recently Deleted is for notes.
  void delete(String id) {
    db.execute(
      'UPDATE commitments SET deleted_at = ?, updated_at = ?, rev = rev + 1 '
      'WHERE id = ? AND deleted_at IS NULL',
      [
        DateTime.now().toUtc().toIso8601String(),
        DateTime.now().toUtc().toIso8601String(),
        id,
      ],
    );
  }

  NexCommitment _fromRow(Row row) => NexCommitment(
    id: row['id'] as String,
    title: row['title'] as String,
    cadence: NexCadence.fromWire(row['cadence'] as String?),
    // Clamped rather than trusted. A zero or negative period would make
    // `nexAdvance` loop without ever moving, which is a hang rather than a
    // wrong answer — and the column is reachable by anyone with the backup
    // file and a copy of sqlite3, which the format deliberately is.
    every: ((row['every'] as int?) ?? 1).clamp(1, 1000),
    dueAt: _local(row['due_at'] as String)!,
    lead: row['lead_seconds'] == null
        ? null
        : Duration(seconds: row['lead_seconds'] as int),
    windowStart: row['window_start'] as int?,
    windowEnd: row['window_end'] as int?,
    lastMetAt: _local(row['last_met_at'] as String?),
    metToday: (row['met_today'] as int?) ?? 0,
    metTodayOn: row['met_today_on'] as String?,
    paused: ((row['paused'] as int?) ?? 0) != 0,
    notify: ((row['notify'] as int?) ?? 1) != 0,
    createdAt: _local(row['created_at'] as String)!,
    updatedAt: _local(row['updated_at'] as String)!,
    rev: (row['rev'] as int?) ?? 1,
  );

  static DateTime? _local(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}
