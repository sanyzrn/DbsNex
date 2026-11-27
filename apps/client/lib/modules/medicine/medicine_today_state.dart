import 'package:nex_client/modules/module_api.dart';

import 'medicine_logic.dart';
import 'medicine_models.dart';
import 'medicine_schedule.dart';
import 'medicine_shared.dart';

/// Where one medicine's routine stands today (the audit pass): how many
/// moments it names, how many are still open, and the first open moment
/// still ahead — all from the person's own routine and their own logs,
/// nothing inferred. A moment with no log is open; it is never "missed".
class MedicineTodayProgress {
  const MedicineTodayProgress({
    required this.total,
    required this.open,
    this.next,
  });

  /// The routine moments this day holds for the medicine.
  final int total;

  /// The ones no log answers yet.
  final int open;

  /// The first open moment still at or after [DateTime.now] when this was
  /// computed, or null when every open moment has already passed (or none
  /// is open). Shown as the thing to act on next.
  final DateTime? next;

  /// The day's routine is fully logged: something was due, and nothing is
  /// left open. Never true of a day the routine names nothing for.
  bool get allLogged => total > 0 && open == 0;

  /// The routine names nothing for this day.
  bool get nothingToday => total == 0;

  /// How [record] stands today, from its own routine and the logs that
  /// answer it. Archived medicines and routines without times have no
  /// moments, so they read as [nothingToday].
  static MedicineTodayProgress of(
    ModuleRecord record,
    List<ModuleRecord> doses,
    DateTime now,
  ) {
    if (MedicineModels.readArchived(record.body)) {
      return const MedicineTodayProgress(total: 0, open: 0);
    }
    final schedule = MedicineSchedule.of(record.body);
    if (!schedule.hasTimes) {
      return const MedicineTodayProgress(total: 0, open: 0);
    }
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final moments = schedule.occurrences(
      from: start.subtract(const Duration(microseconds: 1)),
      until: end,
    );
    if (moments.isEmpty) {
      return const MedicineTodayProgress(total: 0, open: 0);
    }
    // One pass over this medicine's logs, using the same slot-first match
    // as Today and the shared calendar.
    final answered = MedicineShared.answeredKeys(
      MedicineLogic.dosesFor(doses, record.id),
    );
    var open = 0;
    DateTime? next;
    for (final at in moments) {
      final slot =
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
      if (answered.contains('${record.id}|${_day(at)}|$slot')) {
        continue;
      }
      open++;
      if (next == null && !at.isBefore(now)) {
        next = at;
      }
    }
    return MedicineTodayProgress(total: moments.length, open: open, next: next);
  }
}

String _day(DateTime at) =>
    '${at.year}-${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';
