import 'package:flutter/widgets.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_models.dart';
import 'medicine_schedule.dart';
import 'medicine_strings.dart';

/// Turns the routine a person wrote into reminders that ring without the
/// app being open.
///
/// The module API offers one daily ring at a clock face, so this plans the
/// concrete moments instead: the next week of the schedule, at most eight
/// per medicine, each one its own OS alarm. When the cabinet is opened (or
/// the app comes back) the plan is rebuilt: moments still ahead are kept,
/// ones the schedule no longer names are withdrawn, and the rest are
/// armed. Each reminder's title is the medicine's own name and its body
/// names the person and the time — never a dose, a check or a suggestion.
///
/// Nothing here runs while the module is unavailable (`Soon`): the store
/// says so, and every call is wrapped in the caller's guard.
class MedicineReminders {
  const MedicineReminders._();

  /// Every reminder this module owns starts with this, so only its own
  /// alarms are touched when the plan is rebuilt.
  static const _prefix = 'med-';

  /// How far ahead the plan reaches, and how many alarms one medicine may
  /// hold. Enough to cover a week of a three-times-a-day routine without
  /// filling the phone with alarms.
  static const _horizonDays = 7;
  static const _perMedicine = 8;

  /// One reconciliation per store at a time: a reload while the last plan
  /// is still being written waits rather than writing over it.
  static final Set<NexModuleStore> _busy = {};

  static Future<void> sync(
    BuildContext context,
    NexModuleStore store,
    List<ModuleRecord> medicines,
  ) async {
    if (!store.remindersEnabled || _busy.contains(store)) {
      return;
    }
    _busy.add(store);
    try {
      await _sync(context, store, medicines);
    } catch (_) {
      // A reminder that could not be planned is never a reason to take the
      // cabinet down; the next open tries again.
    } finally {
      _busy.remove(store);
    }
  }

  static Future<void> _sync(
    BuildContext context,
    NexModuleStore store,
    List<ModuleRecord> medicines,
  ) async {
    final now = DateTime.now();
    final persian = NexModuleStrings.persian(context);
    final me = medicineStrings(context, 'me');
    final desired =
        <
          String,
          ({ModuleRecord record, String title, String body, DateTime at})
        >{};

    for (final record in medicines) {
      final body = record.body;
      if (MedicineModels.readArchived(body)) {
        continue;
      }
      final name = MedicineModels.readString(body, 'name').trim();
      if (name.isEmpty) {
        continue;
      }
      final schedule = MedicineSchedule.of(body);
      final person = MedicineModels.readPerson(body);
      final who = person.isEmpty ? me : person;
      final occurrences = schedule.occurrences(
        from: now,
        until: now.add(const Duration(days: _horizonDays)),
        limit: _perMedicine,
      );
      for (final at in occurrences) {
        final time = nexDigits(_hhmm(at), persian: persian);
        desired['$_prefix${record.id}-${_stamp(at)}'] = (
          record: record,
          title: name,
          body: medicineStrings(context, 'reminderBody', {
            'person': who,
            'time': time,
          }),
          at: at,
        );
      }
    }

    final existing = await store.list('__reminder');
    final have = {for (final record in existing) record.id};
    for (final key in have) {
      // A moment the schedule no longer names — withdrawn rather than
      // cleared, so an alarm already shown in the shade stays readable.
      if (key.startsWith(_prefix) && !desired.containsKey(key)) {
        await store.withdrawReminder(key);
      }
    }
    for (final entry in desired.entries) {
      if (have.contains(entry.key)) {
        continue;
      }
      final armed = await store.setReminder(
        entry.key,
        sourceKind: MedicineModels.medicine,
        sourceId: entry.value.record.id,
        at: entry.value.at,
        title: entry.value.title,
        body: entry.value.body,
      );
      // No permission, or the module is not available: one refusal is
      // enough, and asking again for every slot would only nag.
      if (!armed) {
        break;
      }
    }
  }

  static String _stamp(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}'
      '${at.month.toString().padLeft(2, '0')}'
      '${at.day.toString().padLeft(2, '0')}'
      '${at.hour.toString().padLeft(2, '0')}'
      '${at.minute.toString().padLeft(2, '0')}';

  static String _hhmm(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
