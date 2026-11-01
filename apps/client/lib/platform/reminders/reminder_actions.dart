part of '../reminders.dart';

/// The buttons under a reminder in the notification shade (2.3.0):
/// **Done** — seen, stop ringing — and, on a one-time note reminder only,
/// **In an hour**, which brings the same reminder back an hour later.
///
/// A repeating reminder has **Done** alone (2.3.1). It comes back by itself
/// at its own time, and an extra copy an hour later sits between two of its
/// real ones and blurs which time it keeps. A recurring item's reminder
/// (the Recurring page) has **Done** too, and there it means what the page's
/// own tick means: met, at the moment the button was pressed, rolled on to
/// its next turn.
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

  /// Marks a recurring item's notification, so a tap or a button on it is
  /// never read as a note's.
  static const commitmentPrefix = 'nex:commitment:';

  static const _ackedKey = 'reminders.acked';
  static const _metKey = 'reminders.met';
  static const _languageKey = 'reminders.language';
  static String _textKey(String noteId) => 'reminders.text.$noteId';

  static List<AndroidNotificationAction> androidActions(
    NexChannelText text, {
    bool snoozable = true,
  }) => [
    AndroidNotificationAction(
      done,
      text.done,
      showsUserInterface: false,
      cancelNotification: true,
    ),
    if (snoozable)
      AndroidNotificationAction(
        snooze,
        text.snooze,
        showsUserInterface: false,
        cancelNotification: true,
      ),
  ];

  /// How a note's reminder looks: the note's words, its two buttons, and
  /// nothing on the lock screen when the app lock asks for that.
  static NotificationDetails noteDetails({
    required String? body,
    required bool secret,
    NexChannelText? text,
    bool repeating = false,
  }) {
    final words = text ?? NexReminders._text;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        NexReminders._channelId,
        words.reminders,
        channelDescription: words.remindersAbout,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: nexNotificationStyle(body),
        visibility: secret ? NotificationVisibility.secret : null,
        actions: androidActions(words, snoozable: !repeating),
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  /// How a recurring item's reminder looks: its title, and **Done** alone —
  /// met now, on to its next turn (2.3.1).
  static NotificationDetails commitmentDetails({required bool secret}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          NexReminders._channelId,
          NexReminders._text.reminders,
          styleInformation: nexNotificationStyle(null),
          channelDescription: NexReminders._text.remindersAbout,
          importance: Importance.high,
          priority: Priority.high,
          visibility: secret ? NotificationVisibility.secret : null,
          actions: androidActions(NexReminders._text, snoozable: false),
        ),
        iOS: const DarwinNotificationDetails(),
      );

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

  /// The recurring items a **Done** was pressed for, with when it was
  /// pressed, read once and cleared.
  static Future<List<(String, DateTime)>> takeMet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getStringList(_metKey) ?? const [];
      if (raw.isNotEmpty) await prefs.remove(_metKey);
      return [
        for (final entry in raw)
          if (entry.lastIndexOf('|') case final bar when bar > 0)
            if (int.tryParse(entry.substring(bar + 1)) case final ms?)
              (
                entry.substring(0, bar),
                DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
              ),
      ];
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
        (response.actionId != done && response.actionId != snooze)) {
      return null;
    }
    final commitment = noteId.startsWith(commitmentPrefix);
    if (noteId.startsWith('nex:') && !commitment) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (commitment) {
      if (response.actionId != done) return null;
      final met = prefs.getStringList(_metKey) ?? const [];
      final at = DateTime.now().toUtc().millisecondsSinceEpoch;
      await prefs.setStringList(_metKey, [
        ...met,
        '${noteId.substring(commitmentPrefix.length)}|$at',
      ]);
      return noteId;
    }
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
      title: nexNotificationText(title),
      body: nexNotificationText(body),
      scheduledDate: at,
      notificationDetails: NexReminderActions.noteDetails(
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
