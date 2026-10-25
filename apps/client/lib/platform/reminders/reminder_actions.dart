part of '../reminders.dart';

/// The two buttons under a note's reminder in the notification shade (2.3.0):
/// **Done** — seen, stop ringing — and **In an hour**, which brings the same
/// reminder back an hour later.
///
/// Both work without opening the app. Android hands a button that shows no UI
/// to a fresh background isolate ([nexReminderActionInBackground]), which has
/// no database and no app state — only the notification plugin and shared
/// preferences. So what such a button needs is kept where that isolate can
/// reach it: the words of each scheduled reminder (to show them again an hour
/// later) and the language of the buttons. "Done" is left as a note in
/// preferences, and the app reads it the next time it is in front.
abstract final class NexReminderActions {
  static const done = 'nex.done';
  static const snooze = 'nex.snooze';

  /// How long "later" is. One hour: long enough to finish what was in hand,
  /// short enough to still be today.
  static const snoozeFor = Duration(hours: 1);

  static const _ackedKey = 'reminders.acked';
  static const _languageKey = 'reminders.language';
  static String _textKey(String noteId) => 'reminders.text.$noteId';

  static List<AndroidNotificationAction> androidActions(NexChannelText text) =>
      [
        AndroidNotificationAction(
          done,
          text.done,
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          snooze,
          text.snooze,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];

  /// Keeps what a reminder says, so "In an hour" can say it again.
  static Future<void> remember(
    String noteId, {
    required String title,
    required String? body,
    required bool secret,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_textKey(noteId), [
        title,
        body ?? '',
        secret ? '1' : '0',
      ]);
    } catch (_) {}
  }

  static Future<void> forget(String noteId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_textKey(noteId));
    } catch (_) {}
  }

  /// Which language the buttons are in, for the isolate that has no locale.
  static Future<void> rememberLanguage({required bool persian}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, persian ? 'fa' : 'en');
    } catch (_) {}
  }

  /// The notes a "Done" was pressed for while the app was not looking, read
  /// once and cleared.
  static Future<List<String>> takeAcknowledged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Written by another isolate: this one's cache does not have it.
      await prefs.reload();
      final ids = prefs.getStringList(_ackedKey) ?? const [];
      if (ids.isNotEmpty) await prefs.remove(_ackedKey);
      return ids;
    } catch (_) {
      return const [];
    }
  }

  /// Does what the button says, wherever the tap landed. Returns the note it
  /// was about, or null when the response was not one of these buttons.
  static Future<String?> handle(
    NotificationResponse response,
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final noteId = response.payload;
    if (noteId == null ||
        noteId.isEmpty ||
        noteId.startsWith('nex:') ||
        (response.actionId != done && response.actionId != snooze)) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (response.actionId == done) {
      final acked = prefs.getStringList(_ackedKey) ?? const [];
      if (!acked.contains(noteId)) {
        await prefs.setStringList(_ackedKey, [...acked, noteId]);
      }
      return noteId;
    }
    final text = prefs.getStringList(_textKey(noteId));
    final language = prefs.getString(_languageKey) == 'fa'
        ? NexChannelText.fa
        : NexChannelText.en;
    final title = (text != null && text.isNotEmpty && text[0].isNotEmpty)
        ? text[0]
        : 'Nex';
    final body = (text != null && text.length > 1 && text[1].isNotEmpty)
        ? text[1]
        : null;
    final secret = text != null && text.length > 2 && text[2] == '1';
    tz_data.initializeTimeZones();
    final at = tz.TZDateTime.from(
      DateTime.now().toUtc().add(snoozeFor),
      tz.UTC,
    );
    Future<void> arm(AndroidScheduleMode mode) => plugin.zonedSchedule(
      id: NexReminders.snoozeIdFor(noteId),
      title: title,
      body: body,
      scheduledDate: at,
      notificationDetails: NexReminders.noteDetails(
        body: body,
        secret: secret,
        text: language,
      ),
      androidScheduleMode: mode,
      payload: noteId,
    );
    try {
      await arm(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      // No exact alarms allowed on this phone: a few minutes late is still
      // "in an hour".
      try {
        await arm(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (_) {}
    }
    return noteId;
  }
}

/// Where Android sends a reminder button pressed while the app is not in
/// front: a fresh isolate with plugins and nothing else.
@pragma('vm:entry-point')
Future<void> nexReminderActionInBackground(
  NotificationResponse response,
) async {
  DartPluginRegistrant.ensureInitialized();
  final plugin = FlutterLocalNotificationsPlugin();
  try {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_nex'),
      ),
    );
  } catch (_) {}
  await NexReminderActions.handle(response, plugin);
}
