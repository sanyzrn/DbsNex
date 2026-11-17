import 'package:flutter/widgets.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_models.dart';
import 'medicine_schedule.dart';
import 'medicine_strings.dart';

/// Turns the routine a person wrote into reminders that ring without the
/// app being open.
///
/// Planned when Nex starts and each time it comes back to the front
/// ([MedicineModule.keepUp], 2.8.4), and again when the cabinet is opened —
/// never only on opening it: a reminder that waits for its screen to be
/// opened stops ringing for whoever does not open it, the worst bug this
/// module can have.
///
/// A routine every day with no end — the usual one — rings through the
/// platform's daily reminder, one per time of day, which keeps ringing
/// however long the app stays closed. Any other routine (some weekdays,
/// every N days, an end date) is planned as its concrete moments over the
/// next week, enough for four a day. Moments still ahead are kept, ones the
/// routine no longer names are withdrawn, the rest are armed. Each reminder's
/// title is the medicine's own name and its body names the person and the
/// time — never a dose, a check or a suggestion.
///
/// Nothing here runs while the module is unavailable (`Soon`): the store
/// says so.
class MedicineReminders {
  const MedicineReminders._();

  /// Every reminder this module owns starts with this, so only its own
  /// alarms are touched when the plan is rebuilt.
  static const _prefix = 'med-';

  /// How far ahead a non-daily routine is planned, and how many alarms one
  /// medicine may hold: a week of four a day. And how many the whole
  /// cabinet may hold, well under what the system allows an app.
  static const _horizonDays = 8;
  static const _perMedicine = 32;
  static const _cabinet = 160;

  /// One plan at a time: a reload while the last plan is still being written
  /// waits for it rather than writing over it.
  static Future<void>? _running;

  /// From the cabinet, in the language it is showing.
  static Future<void> sync(
    BuildContext context,
    NexModuleStore store,
    List<ModuleRecord> medicines,
  ) => plan(store, medicines, AppLocalizations.of(context));

  /// From anywhere, in the language [l10n] is in — the module's keepUp has
  /// no screen.
  static Future<void> plan(
    NexModuleStore store,
    List<ModuleRecord> medicines,
    AppLocalizations l10n,
  ) async {
    if (!store.remindersEnabled) return;
    for (var running = _running; running != null; running = _running) {
      await running;
    }
    final done = _plan(store, medicines, l10n);
    _running = done;
    try {
      await done;
    } catch (_) {
      // A reminder that could not be planned is never a reason to take the
      // cabinet down; the next start or open tries again.
    } finally {
      if (identical(_running, done)) _running = null;
    }
  }

  static Future<void> _plan(
    NexModuleStore store,
    List<ModuleRecord> medicines,
    AppLocalizations l10n,
  ) async {
    final now = DateTime.now();
    final persian = l10n.localeName.startsWith('fa');
    final me = medicineStrings.text(l10n, 'me');
    final desired =
        <
          String,
          ({
            ModuleRecord record,
            String title,
            String body,
            DateTime at,
            bool daily,
          })
        >{};
    String bodyFor(String who, DateTime at) => medicineStrings.text(
      l10n,
      'reminderBody',
      {'person': who, 'time': nexDigits(_hhmm(at), persian: persian)},
    );

    for (final record in medicines) {
      if (desired.length >= _cabinet) break;
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
      final today = DateTime(now.year, now.month, now.day);
      final everyDay =
          schedule.weekdays.isEmpty &&
          schedule.everyDays == null &&
          schedule.endsOn == null &&
          (schedule.startsOn == null || !schedule.startsOn!.isAfter(today));
      if (everyDay) {
        for (final time in schedule.times) {
          final at = MedicineSchedule.at(today, time);
          if (at == null) continue;
          desired['$_prefix${record.id}-d${time.replaceAll(':', '')}'] = (
            record: record,
            title: name,
            body: bodyFor(who, at),
            at: at,
            daily: true,
          );
        }
        continue;
      }
      final occurrences = schedule.occurrences(
        from: now,
        until: now.add(const Duration(days: _horizonDays)),
        limit: _perMedicine,
      );
      for (final at in occurrences) {
        desired['$_prefix${record.id}-${_stamp(at)}'] = (
          record: record,
          title: name,
          body: bodyFor(who, at),
          at: at,
          daily: false,
        );
      }
    }

    final existing = await store.list('__reminder');
    final have = {for (final record in existing) record.id};
    for (final key in have) {
      // A moment the routine no longer names — withdrawn rather than
      // cleared, so an alarm already shown in the shade stays readable.
      if (key.startsWith(_prefix) && !desired.containsKey(key)) {
        await store.withdrawReminder(key);
      }
    }
    for (final MapEntry(:key, :value) in desired.entries) {
      if (have.contains(key)) {
        continue;
      }
      final arm = value.daily ? store.setDailyReminder : store.setReminder;
      final armed = await arm(
        key,
        sourceKind: MedicineModels.medicine,
        sourceId: value.record.id,
        at: value.at,
        title: value.title,
        body: value.body,
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
