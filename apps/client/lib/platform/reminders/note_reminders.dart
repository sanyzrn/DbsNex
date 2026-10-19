part of '../reminders.dart';

/// Asking for permission, and a note's own reminder. Split out of
/// NexReminders (REL-10).
extension NexNoteReminders on NexReminders {
  Future<bool> requestPermission() async {
    if (!NexReminders.supported) return false;
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
          posting =
              requested ?? await android.areNotificationsEnabled() ?? false;
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
      //
      // And it is shown at most once per install, not once per reminder: on
      // a default Android 14+ phone the permission is off, so every reminder
      // used to bounce the user to system Settings whether they had already
      // said no or not. The gate latches after the first ask.
      final alreadyExact = _exactAlarms;
      var gateSaysAsk = true;
      try {
        gateSaysAsk = await shouldRequestExactAlarms?.call() ?? true;
      } catch (_) {
        gateSaysAsk = true;
      }
      if (!alreadyExact && gateSaysAsk) {
        try {
          await android.requestExactAlarmsPermission();
          onExactAlarmsRequested?.call();
        } catch (_) {
          // Nothing to do: the state is read below either way.
        }
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
    if (!NexReminders.supported || when == null) return;
    // Cleared on entry. It reports what happened to *this* alarm, and a value
    // left over from an earlier one is how a reminder that was scheduled
    // perfectly well gets announced as having failed.
    lastError = null;
    await initialise();
    // No cancel first: scheduling under the same id below replaces the alarm,
    // and a cancel would also clear the reminder already showing (2.1.9).
    // A time already past is not an error — it is a reminder that was missed
    // while the app was not running, and firing it now would be a surprise
    // hours late. The note keeps its due date so the user can see it lapsed.
    //
    // A repeating one is different: its start time being in the past is the
    // normal state after the first firing, and the whole point is that it
    // comes back. It is moved forward to the next occurrence instead.
    final at = note.dueRepeat == NoteRepeat.once
        ? when
        : NexReminders.computeNextOccurrence(
            when,
            note.dueRepeat,
            DateTime.now(),
          );
    if (!at.isAfter(DateTime.now().toUtc())) {
      await _withdraw(NexReminders._idFor(note.id));
      _reportInitialisationWarning();
      return;
    }

    // The same treatment a card gets: a reminder is the note's words on a
    // lock screen, and nobody wants to read the markers there either.
    final body = NexMarkdownText.preview(note.displayText ?? '').trim();
    try {
      await _plugin.zonedSchedule(
        id: NexReminders._idFor(note.id),
        // The note's own words are the title: a reminder saying "Nex" tells
        // someone nothing at the moment they most need to know what it is.
        title: body.isEmpty
            ? 'Nex'
            : NexReminders._clamp(body.split('\n').first, 60),
        body: body.isEmpty ? null : NexReminders._clamp(body, 1200),
        scheduledDate: NexReminders.scheduledDateFor(at),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            NexReminders._channelId,
            NexReminders._text.reminders,
            channelDescription: NexReminders._text.remindersAbout,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: body.isEmpty
                ? null
                : BigTextStyleInformation(NexReminders._clamp(body, 1200)),
            visibility: hideOnLockScreen?.call() ?? false
                ? NotificationVisibility.secret
                : null,
          ),
          iOS: const DarwinNotificationDetails(),
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
      lastError = await _verify(NexReminders._idFor(note.id));
      // What the OS was told, in its own terms: the instant, the wall clock
      // it resolves to, and the zone that resolved it. `_verify` can only say
      // that *an* alarm with this id exists — the plugin's queue does not
      // carry a time — so without this line nothing in the app or its
      // diagnostics can answer "set for when?" after the fact.
      final scheduled = NexReminders.scheduledDateFor(at);
      onDiagnostic?.call(
        'reminder ${note.id} -> ${scheduled.toIso8601String()} '
        '(${tz.local.name}, repeat ${note.dueRepeat.wireName}, '
        'exact $_exactAlarms)${lastError == null ? '' : ' — $lastError'}',
      );
    } catch (error) {
      // Too many pending alarms, a platform that changed its mind, a channel
      // that never registered. Still not an error thrown at someone mid-
      // capture — the due date stays on the note either way — but no longer
      // invisible: [lastError] is what the sheet reads before telling anyone
      // their reminder is set.
      lastError = '$error';
    }
    // A schedule that succeeded does not get to hide the timezone problem:
    // on a phone whose zone never loaded, "set for 9:00" was quietly set for
    // a different 9:00 than the one on the clock.
    _reportInitialisationWarning();
  }
}
