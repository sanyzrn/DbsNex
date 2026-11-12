part of '../nex_services.dart';

/// One "ringing" state for a reminder, shared by the notification shade and
/// the timeline (2.3.0).
///
/// A reminder that has rung and not been looked at rings in both places: its
/// notification stays in the shade, and its card shows a swinging bell in
/// place of its type icon. Answering it in either place answers it in both —
/// opening the card takes the notification out of the shade, and **Done** in
/// the shade stops the bell on the card. Nothing else does: opening the app,
/// scrolling past the card, or the reminder's time passing leave both alone.
extension NexRingingServices on NexServices {
  /// Brings [ringing] up to date with the shade, and with any **Done**
  /// pressed while the app was away. Cheap: one read of the shade.
  Future<void> syncRinging() async {
    final acknowledged = await settleReminderAcks();
    final shown = await reminders.shownNoteIds();
    final next = {..._preferences.ringingNotes, ...shown}
      ..removeAll(acknowledged);
    // Only notes ring on a card: a note deleted while ringing, or an id from
    // an older recurring item's notification, has no card to stop it, and
    // stayed in the set for good (2.3.1).
    for (final id in [...next]) {
      final note = await worker.getById(id);
      if (note == null || note.deletedAt != null) next.remove(id);
    }
    await _setRinging(next);
  }

  /// Applies the **Done** presses the notification isolate left behind to the
  /// note itself, and answers which notes were settled.
  ///
  /// The preference list is a hand-off, not the fact. A button that shows no
  /// UI is handled in an isolate with no database, so the only thing it can
  /// do is leave the note id where the app will read it. This is that list's
  /// one reader: it writes [Note.reminderAckedAt] once, before either the
  /// timeline or the daily nudge looks at the note. Whichever of them runs
  /// first can no longer decide whether an answered reminder is mentioned.
  ///
  /// Idempotent: callers share one flight, and a second launch that finds the
  /// list empty has every answer already in the library.
  Future<Set<String>> settleReminderAcks() {
    final running = _ackFlight;
    if (running != null) return running;
    late final Future<Set<String>> flight;
    flight = _applyAcknowledgements().whenComplete(() {
      if (identical(_ackFlight, flight)) _ackFlight = null;
    });
    _ackFlight = flight;
    return flight;
  }

  Future<Set<String>> _applyAcknowledgements() async {
    final acknowledged = (await reminders.takeAcknowledged()).toSet();
    if (acknowledged.isEmpty) return const {};
    final at = DateTime.now().toUtc();
    final settled = <String>{};
    for (final id in acknowledged) {
      try {
        await worker.markReminderAcked(id, at);
        settled.add(id);
      } catch (error) {
        unawaited(NexCrashLog.handled('reminder.ack', error));
        // The hand-off was cleared before the write. Put this one back so the
        // next sync can make it durable instead of losing the answer.
        await NexReminderActions.requeueAcknowledged([id]);
      }
    }
    if (settled.isEmpty) return const {};
    // The same answer stops the card's bell, whichever consumer asked first.
    // The persisted set is edited on its own rather than through [_setRinging]:
    // at launch the notifier is still empty while this set may not be, and
    // writing the notifier over it would erase the bells that are still real.
    final persisted = _preferences.ringingNotes..removeAll(settled);
    await _preferences.setRingingNotes(persisted);
    final live = {...ringing.value}..removeAll(settled);
    if (!setEquals(live, ringing.value)) {
      ringing.value = Set.unmodifiable(live);
    }
    return settled;
  }

  /// Recurring items met with **Done** in the shade, each at the moment it
  /// was pressed. Answers how many were moved on.
  ///
  /// Only an item still waiting on the turn that rang is moved on: one that
  /// was ticked in the app since, or edited to a later time, already has.
  Future<int> applyMetFromShade() async {
    var moved = 0;
    for (final (id, at) in await reminders.takeMet()) {
      final current = (await commitments())
          .where((c) => c.id == id)
          .firstOrNull;
      if (current == null || current.paused) continue;
      if (current.dueAt.isAfter(at.add(const Duration(minutes: 1)))) continue;
      if (await markCommitmentMet(id, at: at.toLocal()) != null) moved++;
    }
    return moved;
  }

  /// A note whose reminder was just tapped, or found ringing.
  Future<void> ring(String noteId) async {
    if (ringing.value.contains(noteId)) return;
    await _setRinging({...ringing.value, noteId});
  }

  /// The note was looked at: stop the bell, and take its notification out of
  /// the shade (putting back the next time of a repeating one).
  Future<void> answerRinging(String noteId) async {
    // Only a note that is ringing has a notification to take away; anything
    // else leaves the alarm queue alone.
    if (!ringing.value.contains(noteId)) return;
    await _setRinging({...ringing.value}..remove(noteId));
    final note = await worker.getById(noteId);
    await reminders.dismissShown(
      noteId,
      note == null || note.deletedAt != null ? null : note,
    );
  }

  /// **Done** was pressed in the shade while the app was running.
  ///
  /// The answer is written to the note here too, rather than left to the
  /// background isolate's hand-off: while the app is in front that button is
  /// delivered to it directly, and a durable fact that exists only when the
  /// other path happened to run is the same ordering bug in a new place.
  Future<void> acknowledgeRinging(String noteId) async {
    try {
      await worker.markReminderAcked(noteId, DateTime.now().toUtc());
    } catch (error) {
      unawaited(NexCrashLog.handled('reminder.ack', error));
      // The next sync retries what this call could not write.
      await NexReminderActions.requeueAcknowledged([noteId]);
    }
    // Today's plan may already be armed with a line about this reminder.
    _queueDailyNudge();
    if (!ringing.value.contains(noteId)) return;
    await _setRinging({...ringing.value}..remove(noteId));
  }

  Future<void> _setRinging(Set<String> ids) async {
    if (setEquals(ids, ringing.value)) return;
    ringing.value = Set.unmodifiable(ids);
    await _preferences.setRingingNotes(ids);
  }
}
