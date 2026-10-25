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
    final acknowledged = await reminders.takeAcknowledged();
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
  Future<void> acknowledgeRinging(String noteId) async {
    if (!ringing.value.contains(noteId)) return;
    await _setRinging({...ringing.value}..remove(noteId));
  }

  Future<void> _setRinging(Set<String> ids) async {
    if (setEquals(ids, ringing.value)) return;
    ringing.value = Set.unmodifiable(ids);
    await _preferences.setRingingNotes(ids);
  }
}
