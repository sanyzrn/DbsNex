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
    // Re-armed in place; a cancel would also clear one already showing
    // (2.1.9).
    if (!at.isAfter(DateTime.now())) {
      await _withdraw(moduleId(module, key));
      return false;
    }
    final target = NexModuleTarget(
      module,
      kind: sourceKind,
      id: sourceId,
      key: key,
      day:
          '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}',
    );
    final secret = hideOnLockScreen?.call() ?? false;
    if (habitCounted != null) {
      await NexHabitNotificationActions.remember(
        target.payload,
        title: title,
        body: body,
        counted: habitCounted,
        secret: secret,
      );
    }
    lastError = null;
    try {
      await _plugin.zonedSchedule(
        id: moduleId(module, key),
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
                  visibility: NotificationVisibility.private,
                ),
                iOS: const DarwinNotificationDetails(),
              ),
        androidScheduleMode: _scheduleMode,
        // A habit's nudge rings at the same wall time every day, so it
        // is scheduled once and repeated by the system.
        matchDateTimeComponents: daily ? DateTimeComponents.time : null,
        payload: target.payload,
      );
      return true;
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
    if (key != null) {
      await _plugin.cancel(id: moduleId(module, key));
    }
    for (final request in await _plugin.pendingNotificationRequests()) {
      final target = NexModuleTarget.parse(request.payload);
      if (target?.module == module && (key == null || target?.key == key)) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  static int moduleId(String module, String key) =>
      NexReminders.idFor('module:${module.length}:$module:$key');
}
