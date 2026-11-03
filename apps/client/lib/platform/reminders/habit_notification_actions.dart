part of '../reminders.dart';

/// Shade actions use the same durable queue as recurring reminders. One key
/// per habit/day makes repeated taps idempotent and avoids a shared list race.
abstract final class NexHabitNotificationActions {
  static const done = 'nex.habit.done';
  static const progress = 'nex.habit.progress';
  static const snooze = 'nex.habit.snooze';
  static const _prefix = 'reminders.habitDone.';

  static NotificationDetails details({
    required String? body,
    required bool counted,
    required bool secret,
    NexChannelText? text,
  }) {
    final words = text ?? NexReminders._text;
    final fa = words == NexChannelText.fa;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        NexReminders._channelId,
        words.reminders,
        channelDescription: words.remindersAbout,
        importance: Importance.high,
        priority: Priority.high,
        visibility: secret
            ? NotificationVisibility.secret
            : NotificationVisibility.private,
        styleInformation: nexNotificationStyle(body),
        actions: [
          AndroidNotificationAction(
            counted ? progress : done,
            counted ? (fa ? 'ثبت پیشرفت' : 'Log progress') : words.done,
            showsUserInterface: counted,
            cancelNotification: counted,
          ),
          AndroidNotificationAction(
            snooze,
            fa ? 'بعداً یادآوری کن' : 'Remind later',
            showsUserInterface: false,
            cancelNotification: false,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  static Future<void> remember(
    String payload, {
    required String title,
    required String body,
    required bool counted,
    required bool secret,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Keep only the metadata needed by recent notifications, once per day.
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    if (prefs.getString('reminders.habitTextGc') != today) {
      final oldest = DateTime(now.year, now.month, now.day - 14);
      for (final key in prefs.getKeys().where(
        (k) => k.startsWith('reminders.habitText.'),
      )) {
        final target = NexModuleTarget.parse(
          key.substring('reminders.habitText.'.length),
        );
        final day = DateTime.tryParse(target?.day ?? '');
        if (day == null || day.isBefore(oldest)) await prefs.remove(key);
      }
      await prefs.setString('reminders.habitTextGc', today);
    }
    await prefs.setStringList('reminders.habitText.$payload', [
      title,
      body,
      counted ? '1' : '0',
      secret ? '1' : '0',
    ]);
  }

  static Future<String?> handle(
    NotificationResponse response,
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final target = NexModuleTarget.parse(response.payload);
    if (target == null ||
        target.module != 'habits' ||
        target.kind != 'habit' ||
        target.id.isEmpty ||
        target.key.isEmpty) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (response.actionId == done) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(target.day)) return null;
      await prefs.setInt(
        'dailyNudge.invalidatedAt',
        DateTime.now().millisecondsSinceEpoch,
      );
      final saved = await prefs.setString(
        '$_prefix${Uri.encodeComponent(target.id)}.${target.day}',
        jsonEncode({
          'payload': target.payload,
          'at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      if (!saved) return null;
      if (response.id != null) {
        try {
          await plugin.cancel(id: response.id!);
        } catch (_) {}
      }
      return target.payload;
    }
    if (response.actionId != snooze) return null;
    final text = prefs.getStringList('reminders.habitText.${target.payload}');
    if (text == null || text.length < 4) return null;
    final words = prefs.getString('reminders.language') == 'fa'
        ? NexChannelText.fa
        : NexChannelText.en;
    tz_data.initializeTimeZones();
    final at = tz.TZDateTime.from(
      DateTime.now().toUtc().add(NexReminderActions.snoozeFor),
      tz.UTC,
    );
    Future<void> arm(AndroidScheduleMode mode) => plugin.zonedSchedule(
      id: NexReminders.snoozeIdFor(target.payload),
      title: nexNotificationText(text[0]),
      body: nexNotificationText(text[1]),
      scheduledDate: at,
      notificationDetails: details(
        body: text[1],
        counted: text[2] == '1',
        secret: text[3] == '1',
        text: words,
      ),
      androidScheduleMode: mode,
      payload: target.payload,
    );
    try {
      await arm(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      try {
        await arm(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (_) {
        return null;
      }
    }
    if (response.id != null) {
      try {
        await plugin.cancel(id: response.id!);
      } catch (_) {}
    }
    return target.payload;
  }

  static Future<List<({String key, NexModuleTarget target, DateTime at})>>
  pending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final rows = <({String key, NexModuleTarget target, DateTime at})>[];
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      try {
        final entry = jsonDecode(prefs.getString(key) ?? '') as Map;
        final target = NexModuleTarget.parse(entry['payload'] as String?);
        final at = DateTime.tryParse('${entry['at']}');
        if (target != null &&
            target.module == 'habits' &&
            target.kind == 'habit' &&
            at != null) {
          rows.add((key: key, target: target, at: at));
        } else {
          await prefs.remove(key);
        }
      } catch (_) {
        await prefs.remove(key);
      }
    }
    return rows;
  }

  static Future<void> acknowledge(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
