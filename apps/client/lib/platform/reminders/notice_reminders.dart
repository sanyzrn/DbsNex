part of '../reminders.dart';

/// The test notification and the model download's progress notices. Split
/// out of NexReminders (REL-10).
extension NexNoticeReminders on NexReminders {
  Future<String?> sendTestNotification({
    required String title,
    required String body,
  }) async {
    if (!NexReminders.supported) return 'not supported on this platform';
    await initialise();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        NexReminders._channelId,
        NexReminders._text.reminders,
        channelDescription: NexReminders._text.remindersAbout,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(
        id: NexReminders._testId,
        title: title,
        body: body,
        notificationDetails: details,
      );
      final when = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));
      await _plugin.zonedSchedule(
        id: NexReminders._testId + 1,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: _scheduleMode,
      );
      return await _verify(NexReminders._testId + 1);
    } catch (error) {
      return '$error';
    }
  }

  /// The download's own notification: one entry, rewritten as it goes.
  ///
  /// Its own channel, at low importance and with `onlyAlertOnce`, because a
  /// progress bar that buzzed on every percent would be the most annoying
  /// thing this app does. Reminders keep theirs at high importance, which is
  /// right for them and wrong for this.
  ///
  /// Deliberately **not** `ongoing`. An ongoing notification cannot be swiped
  /// away, and a download that has no timer on it and stays until it finishes
  /// is exactly the sort of thing someone wants out of their way. Dismissing
  /// it does not touch the transfer, which belongs to the update service.
  Future<void> showDownloadProgress({
    required String title,
    required int percent,
    String? body,
  }) async {
    if (!NexReminders.supported) return;
    await initialise();
    try {
      await _plugin.show(
        id: NexReminders._updateId,
        title: title,
        body: body ?? '$percent%',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            NexReminders._updateChannelId,
            NexReminders._text.updates,
            channelDescription: NexReminders._text.updatesAbout,
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            showProgress: true,
            maxProgress: 100,
            progress: percent.clamp(0, 100),
            ongoing: false,
            autoCancel: false,
          ),
          iOS: const DarwinNotificationDetails(presentSound: false),
        ),
      );
    } catch (_) {
      // A shade entry nobody can post is not worth failing a download over.
    }
  }

  /// Replaces the progress entry with the one that starts the install.
  ///
  /// High importance here, and only here: this is the one moment in the whole
  /// transfer that is worth a buzz, because it is the only one with something
  /// to do.
  Future<void> showDownloadReady({
    required String title,
    required String body,
  }) async {
    if (!NexReminders.supported) return;
    await initialise();
    try {
      await _plugin.show(
        id: NexReminders._updateId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            NexReminders._updateChannelId,
            NexReminders._text.updates,
            channelDescription: NexReminders._text.updatesAbout,
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: NexReminders._updatePayload,
      );
    } catch (_) {
      // See above. The update screen still says the same thing.
    }
  }

  /// Takes the download's entry down.
  Future<void> clearDownloadNotification() async {
    if (!NexReminders.supported) return;
    try {
      await _plugin.cancel(id: NexReminders._updateId);
    } catch (_) {
      // Nothing there to take down, most likely.
    }
  }
}
