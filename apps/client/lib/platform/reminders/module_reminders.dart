part of '../reminders.dart';

extension NexModuleAlarms on NexReminders {
  Future<bool> scheduleModule(
    String module,
    String key, {
    required DateTime at,
    required String title,
    required String body,
    bool daily = false,
    String sourceKind = '',
    String sourceId = '',
    bool? habitCounted,
  }) async {
    if (!NexReminders.supported) return false;
    await initialise();
    final id = moduleId(module, key);
    // Re-armed in place; a cancel would also clear one already showing
    // (2.1.9).
    if (!at.isAfter(DateTime.now())) {
      await _withdraw(id);
      return false;
    }
    // The day on the payload is the day the reminder rings on, *on the wall*,
    // whatever zone the instant was handed over in. `setModuleReminder` passes
    // local time and `restoreModuleReminders` passes the stored UTC instant,
    // and the same reminder has to produce the same payload either way:
    // `applyHabitActions` writes the check a **Done** was pressed for against
    // this day, so reading it off the UTC date logged a check on yesterday's
    // square for every reminder that rings between midnight and the offset
    // from it. The instant is untouched — only the date the buttons carry.
    final day = at.toLocal();
    final target = NexModuleTarget(
      module,
      kind: sourceKind,
      id: sourceId,
      key: key,
      day:
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    );
    final secret = hideOnLockScreen?.call() ?? false;
    // Cleared before anything that can fail, so a failure below is never
    // reported as the previous one.
    lastError = null;
    if (habitCounted != null) {
      // So «remind later» can say the same words again from the isolate that
      // has no database. A preferences failure costs the button, not the
      // reminder — and not an exception out of here, which the caller reads
      // as "could not set it" while the alarm is in fact armed.
      try {
        await NexHabitNotificationActions.remember(
          target.payload,
          title: title,
          body: body,
          counted: habitCounted,
          secret: secret,
        );
      } catch (error) {
        onDiagnostic?.call('habit reminder words: $error');
      }
    }
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: nexNotificationText(title),
        body: nexNotificationText(body),
        scheduledDate: NexReminders.scheduledDateFor(at.toUtc()),
        notificationDetails: habitCounted != null
            ? NexHabitNotificationActions.details(
                body: body,
                counted: habitCounted,
                secret: secret,
              )
            : NotificationDetails(
                android: AndroidNotificationDetails(
                  NexReminders._channelId,
                  NexReminders._text.reminders,
                  styleInformation: nexNotificationStyle(null),
                  channelDescription: NexReminders._text.remindersAbout,
                  importance: Importance.high,
                  priority: Priority.high,
                  // The app lock's rule, not only the habit branch's. A
                  // module reminder carries the item's own words — a
                  // medication, a parking floor, an appointment — and a lock
                  // screen is still a lock screen when the reminder came from
                  // somewhere other than Habits.
                  visibility: secret
                      ? NotificationVisibility.secret
                      : NotificationVisibility.private,
                ),
                iOS: const DarwinNotificationDetails(),
              ),
        androidScheduleMode: _scheduleMode,
        // A habit's nudge rings at the same wall time every day, so it
        // is scheduled once and repeated by the system.
        matchDateTimeComponents: daily ? DateTimeComponents.time : null,
        payload: target.payload,
      );
      // Accepted is not the same as pending — see [_verify], which is what
      // notes and the daily nudge already answer with. Module alarms are
      // rebuilt from the library on every launch, so a drop here is
      // recoverable; saying "set" when the queue does not have it is still a
      // guess, and a guess is what this class spent its longest silence on.
      final problem = await _verify(id);
      if (problem != null) lastError = problem;
      return problem == null;
    } catch (error) {
      lastError = error.toString();
      return false;
    }
  }

  /// Takes back [module]'s alarm [key] if it has not rung yet; one that has
  /// stays on the screen until it is tapped or dismissed.
  Future<void> withdrawModule(String module, String key) async {
    if (!NexReminders.supported) return;
    await initialise();
    await _withdraw(moduleId(module, key));
  }

  Future<void> cancelModule(String module, [String? key]) async {
    if (!NexReminders.supported) return;
    await initialise();
    // Turning a reminder off answers to the item, not to the plugin: a queue
    // that will not read must not leave the module unable to save, which is
    // how "off" becomes a switch that does nothing.
    try {
      if (key != null) {
        await _plugin.cancel(id: moduleId(module, key));
      }
      for (final request in await _plugin.pendingNotificationRequests()) {
        final target = NexModuleTarget.parse(request.payload);
        if (target?.module == module && (key == null || target?.key == key)) {
          await _plugin.cancel(id: request.id);
        }
      }
    } catch (error) {
      onDiagnostic?.call('module alarms: $error');
    }
  }

  static int moduleId(String module, String key) =>
      NexReminders.idFor('module:${module.length}:$module:$key');
}
