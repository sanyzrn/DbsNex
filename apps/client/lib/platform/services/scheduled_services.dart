part of '../nex_services.dart';

/// Scheduled notes: held back until their time. Split out of NexServices
/// (REL-10).
extension NexScheduledServices on NexServices {
  /// Takes the note being written out of the library until [releaseAt] —
  /// the capture sheet's held Send. Its reminder, if it had one, goes: it
  /// was set on a note that is not there any more.
  Future<ScheduledNote?> scheduleNote(String noteId, DateTime releaseAt) async {
    await reminders.cancel(noteId);
    final scheduled = await worker.scheduleNote(noteId, releaseAt);
    if (scheduled == null) return null;
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
    if (arrived.isNotEmpty) await refreshTimeline();
    await _armScheduledTimer();
    return arrived;
  }

  /// Delivers [id] now rather than at its time.
  Future<Note?> releaseScheduledNow(String id) async {
    final note = await worker.releaseScheduledNow(id, DateTime.now());
    await reminders.cancelArrival(id);
    if (note != null) await refreshTimeline();
    await _armScheduledTimer();
    return note;
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
    await worker.discardScheduled(id);
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

  /// Puts every pending alarm back from the library. Run at launch — an OS
  /// alarm does not survive a reinstall or a restore, and the note does.
  Future<void> restoreReminders() async {
    // What came due while the app was closed arrives first, so its alarm is
    // not re-armed below for a moment already past.
    await releaseDueNotes();
    if (!NexReminders.supported) return;
    try {
      // Commitments as well as notes, and not as an afterthought: the sweep
      // inside cancels every pending alarm it cannot account for, so leaving
      // them out of this call is what would destroy their alarms on the next
      // launch.
      await reminders.syncFromLibrary(
        await worker.upcomingReminders(),
        commitments: await worker.listCommitments(),
        // Their arrival alarms too, for the same reason.
        scheduled: await worker.scheduledNotes(),
      );
    } catch (_) {
      // A library that cannot be read here is a library the timeline will
      // fail to read too, and that path already reports it.
    }
  }

  Future<void> setCaption(String id, String caption) =>
      worker.setCaption(id, caption);

  Future<void> setTitle(String id, String? title) => worker.setTitle(id, title);

  Future<void> summarizeInto(String id, String summary) =>
      worker.setSummaryText(id, summary);

  Future<void> setLinkMetadata(String id, {String? title, String? excerpt}) =>
      worker.setLinkMetadata(id, title: title, excerpt: excerpt);

  Future<void> toggleChecklistItem(String id, int index) =>
      worker.toggleChecklistItem(id, index);

  /// Pins [id] when fewer than five notes are already pinned.
  Future<bool> pinNote(String id) => worker.pinNote(id);

  Future<void> unpinNote(String id) => worker.unpinNote(id);

  Future<int> pinnedNoteCount() => worker.pinnedNoteCount();
}
