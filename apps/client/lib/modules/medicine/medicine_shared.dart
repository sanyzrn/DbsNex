import 'package:nex_client/modules/module_api.dart';

import 'medicine_models.dart';
import 'medicine_schedule.dart';

/// Medicine in the shared shape (2.8.4): each time a routine names, done
/// once a log answers it, and each box's expiry. Health data, so every one
/// is private — a calendar shows it only discreetly.
class MedicineShared {
  const MedicineShared({
    required this.medicines,
    this.doses = const [],
    this.boxes = const [],
  });

  final List<ModuleRecord> medicines;
  final List<ModuleRecord> doses;
  final List<ModuleRecord> boxes;

  /// Every moment a log answers, as `medicineId|day|HH:MM` keys: the
  /// routine time the log says it answers (`slot`), and the clock time it
  /// was logged at. A dose logged from the detail sheet carries no slot, so
  /// only its own time can answer a moment — the same match the Today page
  /// makes. A log whose action is neither taken nor skipped answers
  /// nothing: it is not the person's word about a moment.
  static Set<String> answeredKeys(Iterable<ModuleRecord> doses) => {
    for (final dose in doses)
      if (_isAWord(dose))
        if (MedicineModels.readDate(dose.body, 'at') case final at?)
          ..._keysOf(dose, at),
  };

  static bool _isAWord(ModuleRecord dose) {
    final action = MedicineModels.readString(dose.body, 'action');
    return action == MedicineModels.taken || action == MedicineModels.skipped;
  }

  static Iterable<String> _keysOf(ModuleRecord dose, DateTime at) {
    final local = at.toLocal();
    final id = MedicineModels.readString(dose.body, 'medicineId');
    final slot = MedicineModels.readString(dose.body, 'slot');
    return [
      '$id|${_day(local)}|${_hhmm(local)}',
      if (slot.isNotEmpty) '$id|${_day(local)}|$slot',
    ];
  }

  /// Whether [dose] answers the routine moment [time] on the day of [at].
  static bool answers(
    ModuleRecord dose,
    String medicineId,
    DateTime at,
    String time,
  ) {
    final when = MedicineModels.readDate(dose.body, 'at');
    if (when == null || !_isAWord(dose)) {
      return false;
    }
    return _keysOf(dose, when).contains('$medicineId|${_day(at)}|$time');
  }

  /// Everything this module has falling due between [from] and [to].
  List<ModuleDue> duesBetween(DateTime from, DateTime to) {
    final names = <String, String>{};
    final dues = <ModuleDue>[];
    final answered = answeredKeys(doses);
    for (final record in medicines) {
      final name = MedicineModels.readString(record.body, 'name').trim();
      names[record.id] = name;
      if (name.isEmpty || MedicineModels.readArchived(record.body)) continue;
      final schedule = MedicineSchedule.of(record.body);
      // A moment exactly at [from] counts too.
      final start = from.subtract(const Duration(microseconds: 1));
      for (final at in schedule.occurrences(
        from: start,
        until: to,
        limit: 400,
      )) {
        if (at.isAfter(to)) break;
        final slot =
            '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}';
        dues.add(
          ModuleDue(
            id: 'dose:${record.id}:${_day(at)}:$slot',
            recordKind: MedicineModels.medicine,
            recordId: record.id,
            at: at,
            title: name,
            kind: 'dose',
            done: answered.contains('${record.id}|${_day(at)}|$slot'),
            private: true,
          ),
        );
      }
    }
    for (final box in boxes) {
      final day = MedicineModels.readDay(box.body, 'expiresAt');
      if (day == null) continue;
      // A date-only item falls due at local midnight (docs/18, rule 1).
      final at = DateTime(day.year, day.month, day.day);
      if (at.isBefore(from) || at.isAfter(to)) continue;
      final medicineId = MedicineModels.readString(box.body, 'medicineId');
      dues.add(
        ModuleDue(
          id: 'expiry:${box.id}',
          recordKind: MedicineModels.box,
          recordId: box.id,
          at: at,
          title: names[medicineId] ?? '',
          kind: 'expiry',
          private: true,
        ),
      );
    }
    return dues..sort((a, b) => a.at.compareTo(b.at));
  }

  /// One line about [record]: a medicine by its name, and whose it is.
  /// Logs, boxes, places, settings and drafts give none.
  static ModuleSummary? summarize(ModuleRecord record) {
    if (record.kind != MedicineModels.medicine) return null;
    final name = MedicineModels.readString(record.body, 'name').trim();
    if (name.isEmpty) return null;
    final person = MedicineModels.readPerson(record.body);
    final strength = MedicineModels.readString(record.body, 'strength').trim();
    final detail = [person, strength].where((s) => s.isNotEmpty).join(' · ');
    return ModuleSummary(
      title: name,
      detail: detail.isEmpty ? null : detail,
      private: true,
    );
  }

  static String _day(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';

  static String _hhmm(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
