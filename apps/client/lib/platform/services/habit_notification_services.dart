part of '../nex_services.dart';

extension NexHabitShadeServices on NexServices {
  Future<int> applyHabitActions() {
    final pending = _habitActionsPending;
    if (pending != null) return pending;
    return _habitActionsPending = _applyHabitActions().whenComplete(
      () => _habitActionsPending = null,
    );
  }

  Future<int> _applyHabitActions() async {
    var applied = 0;
    final store = NexModuleStore(this, 'habits');
    final locale = _preferences.locale ?? PlatformDispatcher.instance.locale;
    final l10n = lookupAppLocalizations(
      Locale(locale.languageCode == 'fa' ? 'fa' : 'en'),
    );
    for (final entry in await NexHabitNotificationActions.pending()) {
      try {
        final target = entry.target;
        final body = await store.get('habit', target.id);
        final day = DateTime.tryParse(target.day);
        final now = DateTime.now();
        if (moduleRemindersEnabled('habits') &&
            body != null &&
            day != null &&
            dateKeyOf(day) == target.day &&
            !day.isAfter(DateTime(now.year, now.month, now.day))) {
          final habit = Habit.fromBody(target.id, body);
          if (!habit.archived &&
              !habit.counted &&
              HabitMath.dueOn(habit, day)) {
            final id = HabitCheck.idFor(habit.id, target.day);
            if (await store.get('check', id) == null) {
              await store.put('check', id, {
                'habit': habit.id,
                'date': target.day,
                'at': entry.at.toIso8601String(),
              });
              applied++;
            }
            await reminders.cancelModule('habits', target.key);
            await habitArmReminder(store, l10n, habit);
          }
        }
        // A removed/archived habit is harmless; a failed write stays queued.
        await NexHabitNotificationActions.acknowledge(entry.key);
      } catch (_) {
        reminders.onDiagnostic?.call('habit action will retry');
      }
    }
    return applied;
  }
}
