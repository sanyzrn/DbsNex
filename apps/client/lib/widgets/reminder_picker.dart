import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_services.dart';
import 'due_label.dart';
import 'nex_banner.dart';
import 'nex_time_picker.dart';

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
  final choices = <(String, DateTime?)>[
    (l10n.remindLater, now.add(const Duration(hours: 1))),
    (
      l10n.remindEvening,
      DateTime(now.year, now.month, now.day, 20).isAfter(now)
          ? DateTime(now.year, now.month, now.day, 20)
          // Past eight already: "this evening" can only mean tomorrow's.
          : DateTime(now.year, now.month, now.day + 1, 20),
    ),
    (l10n.remindTomorrow, DateTime(now.year, now.month, now.day + 1, 9)),
    (l10n.remindNextWeek, DateTime(now.year, now.month, now.day + 7, 9)),
  ];

  final picked = await showModalBottomSheet<DateTime?>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // What is already set, before the list of things that would replace
          // it. Without this the sheet asked someone to change a reminder they
          // had no way of reading — the only informed thing they could do to
          // it was delete it.
          if (note.dueAt case final due?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.remindChange,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.notifications_active_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: NexSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n.remindCurrent(nexDueExact(sheetContext, due)),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (note.dueAt != null) const Divider(height: 1),
          for (final (label, at) in choices)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(label),
              onTap: () => Navigator.pop(sheetContext, at),
            ),
          ListTile(
            leading: const Icon(Icons.event),
            title: Text(l10n.remindPick),
            onTap: () async {
              final date = await nexPickDate(
                sheetContext,
                first: now,
                last: now.add(const Duration(days: 365 * 5)),
                initial: now.add(const Duration(days: 1)),
              );
              if (date == null || !sheetContext.mounted) return;
              final time = await nexPickTime(
                sheetContext,
                initial: const TimeOfDay(hour: 9, minute: 0),
              );
              if (!sheetContext.mounted) return;
              Navigator.pop(
                sheetContext,
                DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time?.hour ?? 9,
                  time?.minute ?? 0,
                ),
              );
            },
          ),
          if (note.dueAt != null)
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: Text(l10n.remindClear),
              // Null is a real answer here, so the sheet has to be able to
              // tell "cleared" from "dismissed" — which is what the sentinel
              // below is for.
              onTap: () => Navigator.pop(sheetContext, _clearReminder),
            ),
        ],
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
    nexShowBanner(context, message: l10n.remindDenied);
    return false;
  }
  await services.setDueAt(note.id, picked.toUtc());
  if (!context.mounted) return true;
  // What an alarm clock says back. "Reminder set" alone is the same sentence
  // whether the alarm lands in ten minutes or, because a date was mis-tapped,
  // in ten months — and the second case is invisible until it never arrives.
  final failure = services.reminders.lastError;
  nexShowBanner(
    context,
    message: failure != null
        ? l10n.remindNotScheduled
        : l10n.remindSetIn(nexUntilLabel(l10n, picked)),
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
