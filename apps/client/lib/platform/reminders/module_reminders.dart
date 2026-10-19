part of '../reminders.dart';

extension NexModuleAlarms on NexReminders {
  Future<bool> scheduleModule(
    String module,
    String key, {
    required DateTime at,
    required String title,
    required String body,
  }) async {
    if (!NexReminders.supported) return false;
    await initialise();
    // Re-armed in place; a cancel would also clear one already showing
    // (2.1.9).
    if (!at.isAfter(DateTime.now())) {
      await _withdraw(moduleId(module, key));
      return false;
    }
    lastError = null;
    try {
      await _plugin.zonedSchedule(
        id: moduleId(module, key),
        title: title,
        body: body,
        scheduledDate: NexReminders.scheduledDateFor(at.toUtc()),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            NexReminders._channelId,
            NexReminders._text.reminders,
            channelDescription: NexReminders._text.remindersAbout,
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: _scheduleMode,
        payload: 'nex:module:$module',
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
      return;
    }
    for (final request in await _plugin.pendingNotificationRequests()) {
      if (request.payload == 'nex:module:$module') {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  static int moduleId(String module, String key) =>
      NexReminders.idFor('module:${module.length}:$module:$key');
}
