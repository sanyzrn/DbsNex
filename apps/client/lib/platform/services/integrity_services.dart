part of '../nex_services.dart';

/// The contract every library write answers to, and the one lane every
/// reminder-plane change runs in. Split out of NexServices (REL-10).
///
/// Two integrity rules live here because they are not any one caller's to
/// remember:
///
/// 1. **A write that changes the library's shape refreshes the timeline.**
///    The cards bake their tags in, the filter row, the shelves and the
///    home-screen widget all listen to [NexServices.timelineStream] — the
///    model's own comment claimed "every mutation path already refreshes the
///    timeline", and the tag paths did not: a tag renamed, merged, deleted
///    or recoloured anywhere in the app left every one of those surfaces
///    showing the old state until an unrelated capture happened to fire the
///    stream. The service layer now owns the propagation, the way it already
///    owns the reminder behind every due date — a path that only whichever
///    screen remembered is a path the ones that did not miss.
///
/// 2. **The OS alarm queue is rebuilt by exactly one thing at a time.**
///    The launch rebuild's prune ("cancel every alarm the library cannot
///    account for") and the module writes' re-arm both rewrite that queue,
///    and two of them interleaving at their awaits is the narrow window in
///    which an alarm scheduled between one's wanted-set and the other's
///    prune is taken back — a reminder that exists in the library and in
///    no phone. [NexServices._inReminderLane] puts both on the same chain;
///    [nexRefreshReminders]' single-flight already covers launch/resume
///    deliveries against each other, and this covers everything else.
extension NexIntegrityServices on NexServices {
  /// What a write owes the rest of the app once it has landed: the daily
  /// nudge re-planned (it reads the library too) and one canonical timeline
  /// read pushed to every listener.
  ///
  /// Callers that refresh the timeline themselves keep working — a second
  /// identical snapshot is suppressed by the model, and the read is
  /// serialized behind whatever the worker is already doing — so this makes
  /// the forgetful path correct without making the careful one wasteful.
  Future<T> _afterLibraryWrite<T>(Future<T> write) async {
    final result = await write;
    _queueDailyNudge();
    await refreshTimeline();
    return result;
  }

  /// Runs [work] after every reminder-plane change that was queued before it.
  ///
  /// Errors never poison the lane: a failed reconcile still lets the next
  /// one run, which is the rule the worker's own command chain follows —
  /// the difference here being that the things this serializes talk to the
  /// *operating system's* alarm queue, where "half-done" is a state the
  /// library has no mirror of.
  Future<T> _inReminderLane<T>(Future<T> Function() work) {
    final ahead = _reminderLane ?? Future<void>.value();
    final result = ahead.then((_) => work());
    _reminderLane = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
