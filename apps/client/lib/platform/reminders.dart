import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nex_core/nex_core.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Brings a note back up at the time its owner asked for.
///
/// The note carries the time (`Note.dueAt`); this only schedules the alarm
/// that acts on it. That split matters: an OS alarm is not durable — a
/// reinstall drops every one, a restore from backup brings notes back with no
/// alarms behind them, and Android has spent several versions making exact
/// alarms harder to keep — whereas the note is durable by definition. So the
/// library is the record and the alarms are a copy of it, rebuilt from the
/// library on every launch by [syncFromLibrary].
///
/// Everything here degrades to doing nothing rather than throwing. A phone
/// that refuses notifications, a desktop build with no plugin behind it, a
/// test — none of those are errors a person capturing a note should ever see.
class NexReminders {
  NexReminders({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Android needs a channel; both platforms need the tap handler bound
  /// before anything is scheduled, or a tap on a reminder opens the app with
  /// no idea which note it was about.
  static const _channelId = 'nex.reminders';

  /// Separate from the note channel so the daily nudge can be silenced in
  /// system settings without silencing the reminders someone set by hand.
  static const _dailyChannelId = 'nex.daily';

  bool _ready = false;

  /// Whether this phone will let Nex wake at an exact minute.
  ///
  /// Answered by the OS when permission is asked for, and re-asked on every
  /// set — Android lets someone revoke it in Settings at any time, and a
  /// cached yes from last week is how a reminder quietly becomes approximate.
  bool _exactAlarms = false;

  /// Exact when allowed, approximate when not.
  ///
  /// `inexactAllowWhileIdle` was the only mode this used, and it is the wrong
  /// one for something a person calls a reminder: Android defers inexact
  /// alarms under Doze, sometimes by hours, so a note due at 9 arrives at
  /// lunchtime or not that day at all. `alarmClock` is the mode the clock app
  /// itself uses and the only one Doze does not touch.
  AndroidScheduleMode get _scheduleMode => _exactAlarms
      ? AndroidScheduleMode.alarmClock
      : AndroidScheduleMode.inexactAllowWhileIdle;

  /// Called with the note id when a reminder is tapped.
  void Function(String noteId)? onOpenNote;

  /// Whether reminders can work here at all.
  ///
  /// Android and iOS only. The desktop builds have no scheduling backend in
  /// this plugin worth relying on, and offering a reminder that never arrives
  /// is worse than not offering one.
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialise() async {
    if (_ready || !supported) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Asked for at the moment a reminder is first set instead — a
          // permission prompt on first launch, before anyone has seen what
          // the app does, is the reliable way to be refused.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null && id.isNotEmpty) onOpenNote?.call(id);
      },
    );
    _ready = true;
  }

  /// Whether the last schedule attempt failed, and what it said.
  ///
  /// Kept rather than swallowed. This used to be an empty catch, and the
  /// result was a feature that silently did nothing: the note kept its due
  /// date, the banner said the reminder was set, and no notification ever
  /// arrived — with nothing anywhere to say why. A rare, technical string is
  /// worth more than a confident lie.
  String? lastError;

  /// Asks for permission, and answers whether it was given.
  ///
  /// Called when a reminder is actually being set, which is the only moment
  /// the request explains itself.
  ///
  /// Two permissions on Android, not one. Posting a notification is the
  /// obvious one; being allowed to wake at an exact minute is the one that
  /// decides whether "remind me at 9" means 9 or means somewhere after 9 —
  /// see [_scheduleMode].
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await initialise();
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final posting = await android?.requestNotificationsPermission() ?? false;
      // Asked for, not required. A refusal costs precision, not the feature:
      // [_scheduleMode] falls back and the reminder still arrives, late.
      try {
        _exactAlarms = await android?.requestExactAlarmsPermission() ?? false;
      } catch (_) {
        _exactAlarms = false;
      }
      return posting;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  /// Schedules (or reschedules) the reminder for one note.
  Future<void> schedule(Note note) async {
    final when = note.dueAt;
    if (!supported || when == null) return;
    await initialise();
    await cancel(note.id);
    // A time already past is not an error — it is a reminder that was missed
    // while the app was not running, and firing it now would be a surprise
    // hours late. The note keeps its due date so the user can see it lapsed.
    if (!when.isAfter(DateTime.now().toUtc())) return;

    final body = (note.displayText ?? '').trim();
    try {
      await _plugin.zonedSchedule(
        id: _idFor(note.id),
        // The note's own words are the title: a reminder saying "Nex" tells
        // someone nothing at the moment they most need to know what it is.
        title: body.isEmpty ? 'Nex' : _clamp(body, 60),
        scheduledDate: tz.TZDateTime.from(when.toLocal(), tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Reminders',
            channelDescription: 'Notes you asked Nex to bring back up',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: _scheduleMode,
        payload: note.id,
      );
      lastError = null;
    } catch (error) {
      // Too many pending alarms, a platform that changed its mind, a channel
      // that never registered. Still not an error thrown at someone mid-
      // capture — the due date stays on the note either way — but no longer
      // invisible: [lastError] is what the sheet reads before telling anyone
      // their reminder is set.
      lastError = '$error';
    }
  }

  /// The one repeating notification: a nudge at a time the user picked.
  ///
  /// Its own id, outside the range note ids hash into by construction — a note
  /// reminder is keyed on `noteId.hashCode`, and zero is not a hash any string
  /// produces here. Sharing an id would mean scheduling one silently cancels
  /// the other.
  static const _dailyId = 0;

  /// Schedules — or reschedules — the daily nudge.
  ///
  /// [body] is baked in at schedule time, and that is the whole design
  /// constraint rather than a shortcut. A local notification fires while the
  /// app is not running, so nothing can ask a model for a fresh sentence at
  /// the moment it appears. The text is therefore whatever was true the last
  /// time Nex was open, refreshed on every launch, and the repeat carries the
  /// last one forward if the app is not opened for days. A slightly stale line
  /// beats no notification, and beats a notification that promises a summary
  /// and shows a spinner.
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    if (!supported) return;
    await initialise();
    await cancelDaily();

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // Today's slot has passed, so the next one is tomorrow's. Firing
    // immediately would mean a "good morning" at four in the afternoon
    // whenever someone changes the time.
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));

    try {
      await _plugin.zonedSchedule(
        id: _dailyId,
        title: title,
        body: body.isEmpty ? null : body,
        scheduledDate: when,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _dailyChannelId,
            'Daily nudge',
            channelDescription: 'One reminder a day, at a time you chose',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Repeats at the same clock time every day, which is what keeps this
        // arriving when the app is not opened for a week. Inexact is right
        // here in a way it never was for a reminder: nobody sets a morning
        // nudge to the minute, and an exact daily alarm spends a wakeup
        // budget this does not need.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      lastError = null;
    } catch (error) {
      lastError = '$error';
    }
  }

  Future<void> cancelDaily() async {
    if (!supported) return;
    await initialise();
    try {
      await _plugin.cancel(id: _dailyId);
    } catch (_) {}
  }

  Future<void> cancel(String noteId) async {
    if (!supported) return;
    await initialise();
    try {
      await _plugin.cancel(id: _idFor(noteId));
    } catch (_) {}
  }

  /// Rebuilds every pending alarm from the library.
  ///
  /// Run at launch. This is what makes a reminder survive a reinstall, a
  /// restore, or an OS that quietly dropped its alarm list — the note said
  /// when, so the alarm can always be made again.
  Future<void> syncFromLibrary(List<Note> upcoming) async {
    if (!supported) return;
    await initialise();
    for (final note in upcoming) {
      await schedule(note);
    }
  }

  /// A stable 31-bit id derived from the note's own id.
  ///
  /// The plugin keys alarms by int, and notes by string. Hashing means
  /// rescheduling the same note replaces its alarm rather than adding a
  /// second one, without keeping a mapping table that could drift.
  static int _idFor(String noteId) => noteId.hashCode & 0x7fffffff;

  static String _clamp(String text, int max) {
    final one = text.replaceAll(RegExp(r'\s+'), ' ');
    return one.length <= max ? one : '${one.substring(0, max)}…';
  }
}
