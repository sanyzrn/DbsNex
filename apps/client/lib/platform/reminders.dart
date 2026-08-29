import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
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
  Completer<void>? _initialising;

  /// Whether this phone will let Nex wake at an exact minute.
  ///
  /// *Read* on every [initialise] and re-read whenever permission is asked
  /// for. Android lets someone revoke this in Settings at any time, and a
  /// cached yes from last week is how a reminder quietly becomes
  /// approximate — but the worse failure was the opposite one, and it was
  /// live: this was only ever written inside [requestPermission], so on a
  /// cold launch it was false no matter what the OS actually allowed. Every
  /// alarm rebuilt by [syncFromLibrary] and every daily nudge re-armed by the
  /// timeline was therefore downgraded to an inexact alarm on every start,
  /// which Android batches — the reported symptom being a seven o'clock
  /// notification arriving at twenty past.
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

  /// The note whose reminder started the app, if one did.
  ///
  /// [onDidReceiveNotificationResponse] is only called while the app is
  /// already running. A tap that launches it cold is reported once, here, by
  /// the plugin's launch details — so without this the case that matters most
  /// (the phone was in a pocket, the reminder arrived, the notification was
  /// tapped) was the one case that did nothing.
  ///
  /// Read once and cleared by [takeLaunchNoteId]: it describes a single tap,
  /// not a standing state, and a timeline that rebuilt would otherwise keep
  /// re-answering the same one.
  String? _launchNoteId;

  String? takeLaunchNoteId() {
    final id = _launchNoteId;
    _launchNoteId = null;
    return id;
  }

  /// Whether reminders can work here at all.
  ///
  /// Android and iOS only. The desktop builds have no scheduling backend in
  /// this plugin worth relying on, and offering a reminder that never arrives
  /// is worse than not offering one.
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialise() async {
    if (_ready || !supported) return;
    final current = _initialising;
    if (current != null) return current.future;

    final completer = Completer<void>();
    _initialising = completer;
    try {
      await _initialise();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      // The originating caller gets this by `rethrow`; the completer's future
      // is a *second* future carrying the same error, and it has a listener
      // only when another caller happened to be waiting. With no concurrent
      // caller — the ordinary case — it would go unheard, and an unheard
      // error on a future is reported to the zone as an unhandled async
      // exception, which this app writes into its own crash log.
      completer.future.ignore();
      rethrow;
    } finally {
      if (identical(_initialising, completer)) _initialising = null;
    }
  }

  Future<void> _initialise() async {
    tz_data.initializeTimeZones();
    // Loading the database is only half of it. Without this `tz.local` is
    // UTC, and anything scheduled by wall-clock time — the daily nudge, and
    // any repeat matched on the time of day — lands at the wrong hour by
    // exactly the device's offset. A note reminder survived that because it
    // is scheduled from an instant rather than a clock face, which is why the
    // gap went unnoticed.
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (error) {
      // An unknown zone name leaves `tz.local` at UTC, which is where it was
      // before. Recorded rather than swallowed: a reminder an hour out is a
      // harder thing to explain than one that never came.
      lastError = 'timezone: $error';
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_nex'),
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
    // Asked, not assumed, and before anything is scheduled. `canSchedule…`
    // only reads the current state — it shows nobody a prompt — which is what
    // makes it safe here, where a permission request would not be.
    if (Platform.isAndroid) {
      try {
        _exactAlarms =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.canScheduleExactNotifications() ??
            false;
      } catch (error) {
        // An older Android has no such concept and allows exact alarms
        // outright. Deliberately *not* recorded in [lastError]: that field
        // answers "did the alarm I just asked for get taken", and a startup
        // probe writing to it makes every reminder set afterwards report a
        // failure that has nothing to do with it.
        _exactAlarms = false;
      }
    }
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final id = launch?.notificationResponse?.payload;
        if (id != null && id.isNotEmpty) _launchNoteId = id;
      }
    } catch (error) {
      // Not worth failing initialisation over — reminders still schedule and
      // still arrive. Recorded rather than swallowed, because a tap that goes
      // nowhere is exactly the kind of thing that gets called "flaky".
      lastError = 'launch details: $error';
    }
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
    lastError = null;
    try {
      await initialise();
    } catch (error) {
      lastError = 'initialise: $error';
      return false;
    }
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) {
        lastError = 'notification plugin unavailable';
        return false;
      }
      bool posting;
      try {
        posting = await android.areNotificationsEnabled() ?? false;
        if (!posting) {
          final requested = await android.requestNotificationsPermission();
          posting = requested ?? await android.areNotificationsEnabled() ?? false;
        }
      } catch (error) {
        lastError = 'notification permission: $error';
        return false;
      }
      // Asked for, not required. A refusal costs precision, not the feature:
      // [_scheduleMode] falls back and the reminder still arrives, late.
      //
      // The answer is read back rather than taken from the request. On
      // Android `requestExactAlarmsPermission` does not return a decision —
      // it opens the system's "Alarms & reminders" screen and returns false
      // there and then, because the user has not answered yet. Assigning that
      // to [_exactAlarms] overwrote the true state read at startup with a
      // false, on every single reminder anyone set, which quietly put every
      // alarm back on the inexact path this release had just taken it off.
      try {
        await android.requestExactAlarmsPermission();
      } catch (_) {
        // Nothing to do: the state is read below either way.
      }
      try {
        _exactAlarms = await android.canScheduleExactNotifications() ?? false;
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
    // Cleared on entry. It reports what happened to *this* alarm, and a value
    // left over from an earlier one is how a reminder that was scheduled
    // perfectly well gets announced as having failed.
    lastError = null;
    await initialise();
    await cancel(note.id);
    // A time already past is not an error — it is a reminder that was missed
    // while the app was not running, and firing it now would be a surprise
    // hours late. The note keeps its due date so the user can see it lapsed.
    //
    // A repeating one is different: its start time being in the past is the
    // normal state after the first firing, and the whole point is that it
    // comes back. It is moved forward to the next occurrence instead.
    final at = note.dueRepeat == NoteRepeat.once
        ? when
        : _nextOccurrence(when, note.dueRepeat);
    if (!at.isAfter(DateTime.now().toUtc())) return;

    final body = (note.displayText ?? '').trim();
    try {
      await _plugin.zonedSchedule(
        id: _idFor(note.id),
        // The note's own words are the title: a reminder saying "Nex" tells
        // someone nothing at the moment they most need to know what it is.
        title: body.isEmpty ? 'Nex' : _clamp(body, 60),
        scheduledDate: tz.TZDateTime.from(at.toLocal(), tz.local),
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
        // What makes it come back. The plugin re-fires on whichever fields
        // are *not* named here: `time` matches the clock face every day,
        // `dayOfWeekAndTime` matches it on the same weekday.
        matchDateTimeComponents: switch (note.dueRepeat) {
          NoteRepeat.once => null,
          NoteRepeat.daily => DateTimeComponents.time,
          NoteRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
        },
        payload: note.id,
      );
      lastError = await _verify(_idFor(note.id));
    } catch (error) {
      // Too many pending alarms, a platform that changed its mind, a channel
      // that never registered. Still not an error thrown at someone mid-
      // capture — the due date stays on the note either way — but no longer
      // invisible: [lastError] is what the sheet reads before telling anyone
      // their reminder is set.
      lastError = '$error';
    }
  }

  /// The first firing of a repeating reminder that is still ahead.
  ///
  /// A repeat's stored time is when the series *started*, which is in the past
  /// for every repeat that has fired even once — so scheduling it verbatim
  /// would be scheduling a time that has gone, and the alarm would never be
  /// taken. This walks it forward by the repeat's own period, keeping the
  /// clock face it was set at.
  ///
  /// Local time throughout, then back to UTC: "every day at nine" means nine
  /// on the wall, and adding 24 hours across a daylight-saving boundary
  /// silently makes it eight or ten.
  DateTime _nextOccurrence(DateTime start, NoteRepeat repeat) {
    final now = DateTime.now();
    var at = start.toLocal();
    final step = switch (repeat) {
      NoteRepeat.once => 0,
      NoteRepeat.daily => 1,
      NoteRepeat.weekly => 7,
    };
    if (step == 0) return start;
    // A bounded walk rather than `while (true)`: a corrupt start date years in
    // the past should cost a skipped reminder, not a hung isolate.
    for (var guard = 0; guard < 800 && !at.isAfter(now); guard++) {
      at = DateTime(at.year, at.month, at.day + step, at.hour, at.minute);
    }
    return at.toUtc();
  }

  /// Confirms the OS actually took the alarm, and says so when it did not.
  ///
  /// `zonedSchedule` returning without throwing means the request was
  /// accepted, not that anything is pending — and the difference is where
  /// this feature spent its longest silence. Reading the queue back is the
  /// one check that distinguishes "scheduled" from "believed to be
  /// scheduled", and it costs one platform call per reminder.
  ///
  /// Returns null when the alarm is there, and a sentence when it is not.
  Future<String?> _verify(int id) async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      if (pending.any((request) => request.id == id)) return null;
      return 'the system did not keep the alarm';
    } catch (error) {
      // The queue could not be read. Not evidence either way, so it is not
      // reported as a failure — the schedule call itself did not throw.
      return null;
    }
  }

  /// Posts one notification now, and schedules a second a few seconds out.
  ///
  /// A diagnostic, reachable from Settings, and the fastest way to find out
  /// which half of this is broken on a given phone: the immediate one proves
  /// permission and the channel, the delayed one proves scheduling and
  /// delivery. Reminders failed for a year because those two look identical
  /// from inside the app — both are "nothing happened".
  ///
  /// Returns null on success, or what went wrong.
  Future<String?> sendTestNotification({
    required String title,
    required String body,
  }) async {
    if (!supported) return 'not supported on this platform';
    await initialise();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Reminders',
        channelDescription: 'Notes you asked Nex to bring back up',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(
        id: _testId,
        title: title,
        body: body,
        notificationDetails: details,
      );
      final when = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));
      await _plugin.zonedSchedule(
        id: _testId + 1,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: _scheduleMode,
      );
      return await _verify(_testId + 1);
    } catch (error) {
      return '$error';
    }
  }

  /// The two ids [sendTestNotification] uses, kept away from note hashes and
  /// from [_dailyId].
  static const _testId = 1;

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
    lastError = null;
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
        // arriving when the app is not opened for a week.
        //
        // Exact, not inexact. This used to argue that nobody sets a morning
        // nudge to the minute, so an inexact alarm was cheap and good enough —
        // and it is the same argument, on the same phone, that was already
        // proven wrong for note reminders: Android defers an inexact alarm
        // under Doze, sometimes by hours, and on the battery-managed ROMs this
        // app actually runs on, sometimes not at all. A nudge that arrives at
        // an unpredictable hour or never is not a cheaper nudge; it is a
        // broken one. `exactAllowWhileIdle` rather than the `alarmClock` mode
        // reminders use: it is equally exempt from Doze and does not put a
        // standing alarm icon in the status bar, which a daily greeting has
        // not earned.
        androidScheduleMode: _exactAlarms
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      lastError = await _verify(_dailyId);
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
