import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../l10n/app_localizations.dart';
import 'due_label.dart';
import 'nex_dialog.dart';
import '../platform/nex_services.dart';
import 'nex_banner.dart';
import 'reminder_wheel.dart';

/// Asks when a note should come back, and sets or clears the alarm.
///
/// Lifted out of the note detail sheet when a swipe on the timeline was bound
/// to the same thing. It is not a picker so much as a small flow — four
/// shortcuts, a full date-and-time picker behind one of them, a permission
/// request, and a confirmation that says how far off the reminder actually is
/// — and two copies of that would be two places for it to drift.
///
/// Returns whether anything changed, so a caller that shows the note can
/// reload it and one that does not can ignore the answer.
Future<bool> nexPickReminder({
  required BuildContext context,
  required NexServices services,
  required Note note,
}) async {
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();

  // Carried out of the sheet rather than returned beside the time, because
  // the sheet has one exit and it is the button: the repeat is part of the
  // same answer, chosen before it.
  var repeat = note.dueRepeat;

  // The standard sheet chrome (glass surface, drag handle, keyboard inset),
  // not a raw showModalBottomSheet: the last four raw call sites were fixed
  // and this one regressed, which is how a picker ends up with different
  // corner rounding and a different handle than every sheet beside it.
  final picked = await nexShowSheet<DateTime?>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ReminderWheel(
        note: note,
        now: now,
        onSubmit: (when, chosenRepeat) {
          repeat = chosenRepeat;
          Navigator.pop(sheetContext, when);
        },
        // Null is a real answer here, so the sheet has to be able to tell
        // "cleared" from "dismissed" — which is what the sentinel below is
        // for.
        onClear: () => Navigator.pop(sheetContext, _clearReminder),
      ),
    ),
  );
  if (picked == null || !context.mounted) return false;

  if (identical(picked, _clearReminder)) {
    await services.setDueAt(note.id, null);
    return true;
  }

  // Asked for at the moment it is needed, not on first launch: a permission
  // prompt before anyone has seen what the app does is the reliable way to be
  // refused.
  final allowed = await services.reminders.requestPermission();
  if (!context.mounted) return false;
  if (!allowed) {
    final failure = services.reminders.lastError;
    nexShowBanner(
      context,
      message: failure == null
          ? l10n.remindDenied
          : '${l10n.remindNotScheduled} ($failure)',
      kind: NexBannerKind.failed,
    );
    return false;
  }
  await services.setDueAt(note.id, picked.toUtc(), repeat: repeat);
  if (!context.mounted) return true;
  // What an alarm clock says back. "Reminder set" alone is the same sentence
  // whether the alarm lands in ten minutes or, because a date was mis-tapped,
  // in ten months — and the second case is invisible until it never arrives.
  final failure = services.reminders.lastError;
  final until = repeat == NoteRepeat.once
      ? nexUntilLabel(l10n, picked)
      : l10n.remindRepeatingAt(
          nexUntilLabel(l10n, picked),
          nexRepeatLabel(l10n, repeat),
        );
  nexShowBanner(
    context,
    // The OS's own words, appended. Ugly on purpose: "this phone would not
    // take the alarm" is true and completely undiagnosable, and a reminder
    // that silently does not happen is the single most expensive failure this
    // app has had. A rare technical string beats a confident sentence that
    // leaves nobody anything to go on.
    message: failure != null
        ? '${l10n.remindNotScheduled} ($failure)'
        : l10n.remindSetIn(until),
    kind: failure != null ? NexBannerKind.failed : NexBannerKind.done,
  );
  return true;
}

/// How far off a reminder is, in the one unit that reads at that distance.
///
/// Rounded up rather than down: a reminder 90 seconds away is "2 minutes", not
/// "1 minute" — the number people check against is when it *will* go off, and
/// undershooting reads as the app being wrong.
String nexUntilLabel(AppLocalizations l10n, DateTime when) {
  final left = when.difference(DateTime.now());
  if (left.inHours >= 24) {
    return l10n.remindInDays((left.inHours / 24).ceil());
  }
  if (left.inMinutes >= 60) {
    return l10n.remindInHours((left.inMinutes / 60).ceil());
  }
  return l10n.remindInMinutes(
    left.inSeconds <= 0 ? 0 : (left.inSeconds / 60).ceil(),
  );
}

/// A sentinel meaning "take the reminder away", told apart from a dismissed
/// sheet by identity rather than by value.
final _clearReminder = DateTime.utc(1970);
