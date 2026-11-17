part of '../nex_services.dart';

/// Scheduled notes: held back until their time. Split out of NexServices
/// (REL-10).
extension NexScheduledServices on NexServices {
  /// Takes the note being written out of every view until [releaseAt] —
  /// the capture sheet's held Send. Its reminder, if it had one, goes: it
  /// was set on a note that is not arriving.
  ///
  /// The reminder is only cancelled once the note is *actually* waiting:
  /// this used to cancel first and move second, so a note the move refused
  /// — attachments on it, or no words worth delivering — came back with its
  /// alarm already gone and nothing left to re-arm it. The move is the
  /// transaction; the side effects follow it, not lead it.
  Future<ScheduledNote?> scheduleNote(String noteId, DateTime releaseAt) async {
    final scheduled = await worker.scheduleNote(noteId, releaseAt);
    if (scheduled == null) return null;
    await reminders.cancel(noteId);
    await reminders.scheduleArrival(scheduled);
    await refreshTimeline();
    await _armScheduledTimer();
    return scheduled;
  }

  Future<List<ScheduledNote>> scheduledNotes() => worker.scheduledNotes();

  /// Puts every note whose time has come on the timeline.
  ///
  /// Run at launch, on every return to the app, from a timer set for the
  /// next arrival while the app is open, and before a tapped notification
  /// opens its note.
  Future<List<Note>> releaseDueNotes() async {
    final List<Note> arrived;
    try {
      arrived = await worker.releaseDueNotes(DateTime.now());
    } catch (_) {
      return const [];
    }
    await _scheduledArrived(arrived);
    await _armScheduledTimer();
    return arrived;
  }

  /// Delivers [id] now rather than at its time.
  Future<Note?> releaseScheduledNow(String id) async {
    final note = await worker.releaseScheduledNow(id, DateTime.now());
    await reminders.cancelArrival(id);
    if (note != null) await _scheduledArrived([note]);
    await _armScheduledTimer();
    return note;
  }

  Future<void> _scheduledArrived(List<Note> notes) async {
    if (notes.isEmpty) return;
    for (final note in notes) {
      await reminders.cancelArrival(note.id);
      scheduleEnrichment(note.id);
    }
    await _afterNudgeWrite(refreshTimeline());
  }

  Future<bool> rescheduleNote(String id, DateTime releaseAt) async {
    final moved = await worker.rescheduleNote(id, releaseAt);
    if (moved) {
      for (final note in await worker.scheduledNotes()) {
        if (note.id == id) await reminders.scheduleArrival(note);
      }
    }
    await _armScheduledTimer();
    return moved;
  }

  /// Throws a waiting note away. It never reached the library, so there is
  /// no trash and no undo.
  Future<void> discardScheduled(String id) async {
    await _afterNudgeWrite(worker.discardScheduled(id));
    await reminders.cancelArrival(id);
    await _armScheduledTimer();
  }

  /// One timer, for the next arrival, while the app is open — so a note due
  /// at ten lands at ten on a timeline someone is looking at, not at their
  /// next visit.
  Future<void> _armScheduledTimer() async {
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    final List<ScheduledNote> pending;
    try {
      pending = await worker.scheduledNotes();
    } catch (_) {
      return;
    }
    if (pending.isEmpty) return;
    final wait = pending.first.releaseAt.difference(DateTime.now().toUtc());
    _scheduledTimer = Timer(
      (wait.isNegative ? Duration.zero : wait) + const Duration(seconds: 1),
      () => unawaited(releaseDueNotes()),
    );
  }

  /// Rebuilds every pending alarm from the library — and prunes the ones the
  /// library no longer asks for — on the reminder plane's one lane, so a
  /// module write re-arming an alarm beside this sweep cannot have it pruned
  /// as unaccounted-for between the sweep's wanted-set and its cancel loop.
  /// See `NexIntegrityServices`' extension comment.
  Future<void> restoreReminders() async {
    // What came due while the app was closed arrives first, so its alarm is
    // not re-armed below for a moment already past.
    await releaseDueNotes();
    await applyHabitActions();
    if (!NexReminders.supported) return;
    try {
      // Commitments as well as notes, and not as an afterthought: the sweep
      // inside cancels every pending alarm it cannot account for, so leaving
      // them out of this call is what would destroy their alarms on the next
      // launch.
      //
      // The whole read-and-prune is one lane entry: the module reminder ids
      // it prunes against are computed inside, immediately before the sweep,
      // so nothing scheduled in between can slip below the wanted-set.
      await _inReminderLane(() async {
        await reminders.syncFromLibrary(
          await worker.upcomingReminders(),
          commitments: await worker.listCommitments(),
          // Their arrival alarms too, for the same reason.
          scheduled: await worker.scheduledNotes(),
          moduleReminderIds: await restoreModuleReminders(),
        );
      });
    } catch (_) {
      // A library that cannot be read here is a library the timeline will
      // fail to read too, and that path already reports it.
    }
  }

  /// Names a note, and tells the timeline: the card wears the title.
  Future<void> setTitle(String id, String? title) =>
      _afterLibraryWrite(worker.setTitle(id, title));

  /// Captions a note, and tells the timeline: the card wears the caption
  /// where one is set.
  Future<void> setCaption(String id, String caption) =>
      _afterLibraryWrite(worker.setCaption(id, caption));

  Future<void> summarizeInto(String id, String summary) =>
      worker.setSummaryText(id, summary);

  Future<void> setLinkMetadata(
    String id, {
    String? title,
    String? excerpt,
    bool keepTime = false,
  }) => worker.setLinkMetadata(
    id,
    title: title,
    excerpt: excerpt,
    keepTime: keepTime,
  );

  /// Ticks a checklist line, and tells the timeline: the card renders the
  /// ticked state, and the detail sheet was the one caller that never
  /// refreshed it — the line read done on the sheet and undone on the card
  /// until an unrelated change happened to fire the stream.
  Future<void> toggleChecklistItem(String id, int index) =>
      _afterLibraryWrite(worker.toggleChecklistItem(id, index));

  /// Pins [id] when fewer than five notes are already pinned, and tells the
  /// timeline: a pin moves a note to the top of it, which is the timeline's
  /// business to show.
  Future<bool> pinNote(String id) => _afterLibraryWrite(worker.pinNote(id));

  Future<void> setUrgent(String id, bool urgent) async {
    await worker.setUrgent(id, urgent);
    await refreshTimeline();
  }

  Future<void> unpinNote(String id) => _afterLibraryWrite(worker.unpinNote(id));

  Future<int> pinnedNoteCount() => worker.pinnedNoteCount();

  /// Puts [id] to one side: off the home timeline, still searchable, still
  /// carrying its reminder. A null [until] keeps it there until it is
  /// brought back. The service owns the timeline refresh — every caller
  /// already did it, and the one that forgets is the one that used to leave
  /// the home holding a note that was not on it.
  Future<bool> setAside(String id, {DateTime? until}) =>
      _afterLibraryWrite(worker.setAside(id, until: until));

  Future<void> bringBack(String id) => _afterLibraryWrite(worker.bringBack(id));

  Future<List<Note>> listSetAside() => worker.listSetAside();

  Future<int> setAsideCount() => worker.setAsideCount();

  Future<List<String>> releaseDueSetAside() => worker.releaseDueSetAside();
}
