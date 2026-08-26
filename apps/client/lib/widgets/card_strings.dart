import 'package:flutter/widgets.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'due_label.dart';
import 'reminder_picker.dart';

/// The card's screen-reader strings, in the language the user chose.
///
/// `packages/ui` carries no localisations of its own — the same reason
/// `TagFilterRow.allLabel` is passed in from here — so this is the one place
/// that binds the two together. Without it a Persian user running TalkBack
/// heard "text note. Tags: کار": the structure in English, the content in
/// Persian.
NexCardStrings nexCardStrings(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return NexCardStrings(
    // The type name arrives as a wire name ("voice"), so it is translated
    // here rather than interpolated raw.
    noteOfType: (type) => l10n.noteOfType(l10n.noteType(type)),
    tagList: l10n.tagListLabel,
    accentColor: l10n.accentColorLabel,
    relativeTime: (time) => switch (time.unit) {
      NexRelativeUnit.now => l10n.timeNow,
      NexRelativeUnit.minutes => l10n.timeMinutesAgo(time.count),
      NexRelativeUnit.hours => l10n.timeHoursAgo(time.count),
      NexRelativeUnit.days => l10n.timeDaysAgo(time.count),
      NexRelativeUnit.weeks => l10n.timeWeeksAgo(time.count),
      NexRelativeUnit.months => l10n.timeMonthsAgo(time.count),
      NexRelativeUnit.years => l10n.timeYearsAgo(time.count),
    },
    // A repeat has no countdown to give: its stored time is when the series
    // started. It says how often instead, which is the thing worth knowing at
    // a glance about a reminder that keeps coming back.
    dueLabel: (due, repeat) => repeat == NoteRepeat.once
        ? nexDueCountdown(l10n, due)
        : nexRepeatLabel(l10n, repeat),
  );
}
