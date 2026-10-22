import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/display_date.dart';
import '../platform/nex_services.dart';
import 'nex_dialog.dart';
import 'nex_time_picker.dart';

/// What the person chose in [nexPickSetAside]: until when, or null for "until
/// I bring it back". A wrapper, because the sheet's own null means it was
/// dismissed — which is a different answer from "no return time".
class SetAsideChoice {
  const SetAsideChoice(this.until);

  final DateTime? until;
}

/// When a set-aside note should come back, as a handful of answers people
/// actually give — this evening, tomorrow, next week, a date — and "when I say
/// so", which is the one that needs no clock at all.
///
/// The hour is fixed rather than asked: coming back is a morning thing ("have
/// it in front of me when the day starts"), and a time wheel would turn a
/// two-second gesture into a form. A note that needs a precise moment is a
/// reminder, and has one.
Future<SetAsideChoice?> nexPickSetAside({
  required BuildContext context,
  required NexServices services,
}) {
  return nexShowSheet<SetAsideChoice>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: _SetAsideSheet(
        solar: services.solarCalendar,
        onPickDate: () async {
          final now = DateTime.now();
          final day = await nexPickDate(
            sheetContext,
            initial: now.add(const Duration(days: 2)),
            first: DateTime(now.year, now.month, now.day + 1),
            last: DateTime(now.year + 2, now.month, now.day),
            solar: services.solarCalendar,
          );
          if (day == null || !sheetContext.mounted) return;
          Navigator.pop(
            sheetContext,
            SetAsideChoice(DateTime(day.year, day.month, day.day, 8)),
          );
        },
      ),
    ),
  );
}

/// The morning a "tomorrow" or "next week" answer lands on.
const _returnHour = 8;

/// The instants the shortcuts mean, from [now]. Public to the library so the
/// arithmetic can be tested without a sheet.
///
/// "This evening" is only offered while it is still ahead of [now] by more
/// than a little; at 17:50 it would mean ten minutes, which is a different
/// idea from the one the words carry.
List<({NexSetAsideSlot slot, DateTime when})> nexSetAsideSlots(DateTime now) {
  final evening = DateTime(now.year, now.month, now.day, 18);
  return [
    if (evening.difference(now) > const Duration(hours: 1))
      (slot: NexSetAsideSlot.evening, when: evening),
    (
      slot: NexSetAsideSlot.tomorrow,
      when: DateTime(now.year, now.month, now.day + 1, _returnHour),
    ),
    (
      slot: NexSetAsideSlot.nextWeek,
      when: DateTime(now.year, now.month, now.day + 7, _returnHour),
    ),
  ];
}

/// The shortcuts the picker offers beside "until I bring it back".
enum NexSetAsideSlot { evening, tomorrow, nextWeek }

class _SetAsideSheet extends StatelessWidget {
  const _SetAsideSheet({required this.solar, required this.onPickDate});

  final bool solar;
  final Future<void> Function() onPickDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final persian = l10n.localeName == 'fa';
    final slots = nexSetAsideSlots(DateTime.now());

    Widget row({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) => ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      onTap: onTap,
    );

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.setAsideSheetTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: NexSpacing.xs),
          Text(
            l10n.setAsideSheetHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          row(
            icon: Icons.archive_outlined,
            title: l10n.setAsideUntilBack,
            onTap: () => Navigator.pop(context, const SetAsideChoice(null)),
          ),
          for (final entry in slots)
            row(
              icon: switch (entry.slot) {
                NexSetAsideSlot.evening => Icons.nights_stay_outlined,
                NexSetAsideSlot.tomorrow => Icons.wb_sunny_outlined,
                NexSetAsideSlot.nextWeek => Icons.date_range_outlined,
              },
              title: switch (entry.slot) {
                NexSetAsideSlot.evening => l10n.setAsideThisEvening,
                NexSetAsideSlot.tomorrow => l10n.setAsideTomorrow,
                NexSetAsideSlot.nextWeek => l10n.setAsideNextWeek,
              },
              subtitle: nexReadableDate(
                entry.when,
                solar: solar,
                persian: persian,
              ),
              onTap: () => Navigator.pop(context, SetAsideChoice(entry.when)),
            ),
          row(
            icon: Icons.edit_calendar_outlined,
            title: l10n.setAsidePickDate,
            onTap: () => onPickDate(),
          ),
        ],
      ),
    );
  }
}
