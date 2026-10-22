import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart';

import '../l10n/app_localizations.dart';
import '../platform/display_date.dart';
import '../platform/nex_services.dart';
import 'nex_banner.dart';
import 'set_aside_picker.dart';

/// Asks until when, puts every one of [notes] to one side, says so, and
/// offers to take it back.
///
/// One flow for every way in — the hold menu, the detail sheet, a selection of
/// several — so the wording, the undo and the haptics are the same wherever
/// it starts. Returns how many notes were set aside; 0 when the sheet was
/// dismissed or nothing could be.
Future<int> nexSetAsideNotes({
  required BuildContext context,
  required NexServices services,
  required List<Note> notes,
  bool haptics = true,
}) async {
  if (notes.isEmpty) return 0;
  final choice = await nexPickSetAside(context: context, services: services);
  if (choice == null || !context.mounted) return 0;
  final l10n = AppLocalizations.of(context);
  final persian = l10n.localeName == 'fa';
  final solar = services.solarCalendar;
  final until = choice.until;

  final done = <String>[];
  for (final note in notes) {
    if (await services.setAside(note.id, until: until)) done.add(note.id);
  }
  await services.refreshTimeline();
  if (haptics) unawaited(HapticFeedback.mediumImpact());
  if (done.isEmpty || !context.mounted) return done.length;

  final message = done.length > 1
      ? l10n.setAsideGroupDone(done.length)
      : until == null
      ? l10n.setAsideDone
      : l10n.setAsideDoneUntil(
          nexReadableDate(until, solar: solar, persian: persian),
        );
  nexShowBanner(
    context,
    message: message,
    haptics: false,
    actionLabel: l10n.undo,
    onAction: () async {
      for (final id in done) {
        await services.bringBack(id);
      }
      await services.refreshTimeline();
    },
  );
  return done.length;
}

/// Brings [notes] back onto the home timeline and says how many.
Future<void> nexBringBackNotes({
  required BuildContext context,
  required NexServices services,
  required List<Note> notes,
}) async {
  if (notes.isEmpty) return;
  for (final note in notes) {
    await services.bringBack(note.id);
  }
  await services.refreshTimeline();
}
