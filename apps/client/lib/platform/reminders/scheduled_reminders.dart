part of '../reminders.dart';

/// The daily nudge, recurring items, «Cycle», scheduled notes' arrival, and
/// keeping every reminder in step with the library. Split out of
/// NexReminders (REL-10).
extension NexScheduledReminders on NexReminders {
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
    if (!NexReminders.supported) return;
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
        id: NexReminders._dailyId,
        title: title,
        body: body.isEmpty ? null : body,
        scheduledDate: when,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            NexReminders._dailyChannelId,
            NexReminders._text.daily,
            channelDescription: NexReminders._text.dailyAbout,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            // The recap this carries is now as long as there was something
            // to say — up to a short paragraph on a busy week. With no style
            // set, Android shows one line of it and offers no way to reach
            // the rest, so the mornings with the most in them would be the
            // ones the notification said least about.
            styleInformation: body.isEmpty
                ? null
                : BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
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
        // broken one. `exactAllowWhileIdle` rather than `alarmClock`: equally
        // exempt from Doze, and it does not put a standing alarm icon in the
        // status bar, which a daily greeting has not earned.
        //
        // Note reminders used `alarmClock` and have since come here for the
        // same reason — see [_scheduleMode], which is now what this would
        // resolve to anyway. Left spelled out rather than swapped for that
        // getter: this one has never depended on the reminder policy, and
        // making it do so is how the two drift into each other.
        androidScheduleMode: _exactAlarms
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      lastError = await _verify(NexReminders._dailyId);
    } catch (error) {
      lastError = '$error';
    }
  }

  Future<void> cancelDaily() async {
    if (!NexReminders.supported) return;
    await initialise();
    try {
      await _plugin.cancel(id: NexReminders._dailyId);
    } catch (_) {}
  }

  /// A standing obligation's own alarm, at the moment it next falls due.
  ///
  /// A **one-shot**, re-armed whenever the commitment moves. The OS can only
  /// repeat on a clock face (`time`) or a weekday (`dayOfWeekAndTime`), and
  /// neither describes "every eight hours" or "every month" — so rather than
  /// use a repeat that fits two of the five cadences and silently misfits the
  /// rest, each occurrence is scheduled on its own and the next one is set
  /// when this one is met, when the app launches, or when the commitment is
  /// edited.
  ///
  /// The cost of that is honest and worth stating: if the app is never opened
  /// and the notification never tapped, only the next occurrence fires. For a
  /// yearly renewal that is irrelevant; for water every two hours it means
  /// the chain needs the app to be opened sometimes, which it will be,
  /// because tapping the notification opens it.
  Future<void> scheduleCommitment(NexCommitment commitment) async {
    if (!NexReminders.supported) return;
    lastError = null;
    await initialise();
    await cancelCommitment(commitment.id);
    if (!commitment.notify || commitment.paused) return;
    final at = commitment.dueAt;
    // Already past: the moment was missed while the app was not running, and
    // firing now would be a surprise hours late. It still shows as overdue on
    // the screen and in the brief, which is the honest place for it.
    if (!at.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: NexReminders.commitmentIdFor(commitment.id),
        title: NexReminders._clamp(commitment.title, 60),
        scheduledDate: NexReminders.scheduledDateFor(at.toUtc()),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            NexReminders._channelId,
            NexReminders._text.reminders,
            channelDescription: NexReminders._text.remindersAbout,
            importance: Importance.high,
            priority: Priority.high,
            visibility: hideOnLockScreen?.call() ?? false
                ? NotificationVisibility.secret
                : null,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: _scheduleMode,
        payload: commitment.id,
      );
      onDiagnostic?.call(
        'commitment ${commitment.id} -> ${at.toIso8601String()} '
        '(${tz.local.name})',
      );
    } catch (error) {
      lastError = error.toString();
    }
  }

  Future<void> cancelCommitment(String commitmentId) async {
    if (!NexReminders.supported) return;
    await initialise();
    try {
      await _plugin.cancel(id: NexReminders.commitmentIdFor(commitmentId));
    } catch (_) {}
  }

  /// One cycle alarm at [at], or every day at [at]'s time when [daily].
  ///
  /// The words are whatever the caller hands in, and the caller hands in
  /// words that say nothing about a cycle: a lock screen is read by
  /// whoever is holding the phone.
  Future<void> scheduleCycle(
    String key, {
    required DateTime at,
    required String title,
    required String body,
    bool daily = false,
  }) async {
    if (!NexReminders.supported) return;
    lastError = null;
    await initialise();
    await cancelCycle(key);
    var when = tz.TZDateTime.from(at, tz.local);
    final now = tz.TZDateTime.now(tz.local);
    if (daily) {
      while (!when.isAfter(now)) {
        when = when.add(const Duration(days: 1));
      }
    } else if (!when.isAfter(now)) {
      return;
    }
    try {
      await _plugin.zonedSchedule(
        id: NexReminders.cycleIdFor(key),
        title: title,
        body: body.isEmpty ? null : body,
        scheduledDate: when,
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
        matchDateTimeComponents: daily ? DateTimeComponents.time : null,
      );
    } catch (error) {
      lastError = error.toString();
    }
  }

  /// Cancels the cycle alarm [key], or every one of them.
  Future<void> cancelCycle([String? key]) async {
    if (!NexReminders.supported) return;
    await initialise();
    for (final k in key == null ? NexReminders.cycleKeys : [key]) {
      try {
        await _plugin.cancel(id: NexReminders.cycleIdFor(k));
      } catch (_) {}
    }
  }

  /// The notification for a scheduled note arriving (see [ScheduledNote]).
  ///
  /// Its payload is the note's id, which the note keeps when it arrives, so
  /// a tap opens it like any reminder's — once [NexServices.releaseDueNotes]
  /// has put it on the timeline, which the tap handler does first.
  Future<void> scheduleArrival(ScheduledNote note) async {
    if (!NexReminders.supported) return;
    lastError = null;
    await initialise();
    await cancelArrival(note.id);
    if (!note.releaseAt.isAfter(DateTime.now().toUtc())) return;
    final body = NexMarkdownText.preview(note.content).trim();
    try {
      await _plugin.zonedSchedule(
        id: NexReminders.arrivalIdFor(note.id),
        title: body.isEmpty
            ? 'Nex'
            : NexReminders._clamp(body.split('\n').first, 60),
        body: body.isEmpty ? null : NexReminders._clamp(body, 1200),
        scheduledDate: NexReminders.scheduledDateFor(note.releaseAt),
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
        payload: note.id,
      );
      onDiagnostic?.call(
        'scheduled ${note.id} -> ${note.releaseAt.toIso8601String()} '
        '(${tz.local.name})',
      );
    } catch (error) {
      lastError = error.toString();
    }
  }

  Future<void> cancelArrival(String noteId) async {
    if (!NexReminders.supported) return;
    await initialise();
    try {
      await _plugin.cancel(id: NexReminders.arrivalIdFor(noteId));
    } catch (_) {}
  }

  Future<void> cancel(String noteId) async {
    if (!NexReminders.supported) return;
    await initialise();
    try {
      await _plugin.cancel(id: NexReminders._idFor(noteId));
    } catch (_) {}
  }

  /// Rebuilds every pending alarm from the library — and prunes the ones the
  /// library no longer asks for.
  ///
  /// Run at launch. This is what makes a reminder survive a reinstall, a
  /// restore, or an OS that quietly dropped its alarm list — the note said
  /// when, so the alarm can always be made again.
  ///
  /// The prune is the other half of that sentence. This used to only ever
  /// *add*: every alarm the OS still held that the library could not account
  /// for — one left by a restore that rolled the library back, one orphaned
  /// before the delete path learned to cancel — kept firing, and the boot
  /// receiver re-armed each of them at every reboot. The library is the
  /// record, so anything the record does not ask for goes. Reserved ids (the
  /// daily nudge, the download, the diagnostics) are never touched — none of
  /// them is a note, so none of them is in the library to be asked for.
  ///
  /// [commitments] is not optional in spirit, only in signature. The prune
  /// cancels every pending alarm it cannot account for, so a standing
  /// obligation's alarm is destroyed by the next launch unless this list is
  /// what it is checked against. That is the trap in adding a second kind of
  /// thing that owns an alarm: the sweep has to learn about it in the same
  /// change, or the feature works until the app is restarted.
  Future<void> syncFromLibrary(
    List<Note> upcoming, {
    List<NexCommitment> commitments = const [],
    List<ScheduledNote> scheduled = const [],
  }) async {
    if (!NexReminders.supported) return;
    await initialise();

    final wanted = <int>{
      for (final note in upcoming) NexReminders._idFor(note.id),
      for (final commitment in commitments)
        if (commitment.notify && !commitment.paused)
          NexReminders.commitmentIdFor(commitment.id),
      for (final note in scheduled) NexReminders.arrivalIdFor(note.id),
    };
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        final id = request.id;
        // Reserved ids are never touched — none of them is a note, so none of
        // them is in the library to be asked for.
        if (id < NexReminders.reservedIds ||
            NexReminders._cycleIds.contains(id)) {
          continue;
        }
        if (!wanted.contains(id)) {
          try {
            await _plugin.cancel(id: id);
          } catch (_) {}
        }
      }
    } catch (_) {
      // The queue could not be read: adding still happens below, and the
      // ghosts wait for the next launch rather than failing this one.
    }

    for (final note in upcoming) {
      await schedule(note);
    }
    for (final commitment in commitments) {
      await scheduleCommitment(commitment);
    }
    for (final note in scheduled) {
      await scheduleArrival(note);
    }
  }
}
