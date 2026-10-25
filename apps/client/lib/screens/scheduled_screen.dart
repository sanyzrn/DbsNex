import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_services.dart';
import '../widgets/collection_page.dart';
import '../widgets/due_label.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_shelf.dart';
import '../widgets/schedule_picker.dart';

/// The notes on their way: everything held Send scheduled, the soonest
/// first, each with a way to bring it now, move it, or throw it away.
///
/// Without this a note scheduled by mistake — a year out instead of a week
/// — would simply be gone until then, with nothing anywhere to say it was
/// coming.
class ScheduledScreen extends StatefulWidget {
  const ScheduledScreen({super.key, required this.services});

  final NexServices services;

  @override
  State<ScheduledScreen> createState() => _ScheduledScreenState();
}

class _ScheduledScreenState extends State<ScheduledScreen> {
  List<ScheduledNote>? _notes;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    // Anything that came due while this was closed arrives first, so the
    // list never shows a note that is already on the timeline.
    await widget.services.releaseDueNotes();
    final notes = await widget.services.scheduledNotes();
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _sendNow(ScheduledNote note) async {
    await widget.services.releaseScheduledNow(note.id);
    await _reload();
  }

  Future<void> _changeTime(ScheduledNote note) async {
    final when = await nexPickScheduleTime(
      context: context,
      services: widget.services,
    );
    if (when == null) return;
    await widget.services.rescheduleNote(note.id, when.toUtc());
    await _reload();
  }

  Future<void> _discard(ScheduledNote note) async {
    final l10n = AppLocalizations.of(context);
    final ok = await nexShowDialog<bool>(
      context: context,
      builder: (context) => NexAlertDialog(
        title: Text(l10n.scheduledDiscard),
        content: NexDialogBody(child: Text(l10n.scheduledDiscardConfirm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.scheduledDiscard),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.services.discardScheduled(note.id);
    if (mounted) {
      nexShowBanner(context, message: l10n.scheduledDiscard);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notes = _notes;
    final hue = NexHue.sky.on(context);
    return Scaffold(
      appBar: NexAppBar(title: Text(l10n.scheduledTitle)),
      body: switch (notes) {
        null => const NexLoadingList(),
        [] => NexEmptyState(
          icon: Icons.schedule_send_outlined,
          message: l10n.scheduledEmpty,
        ),
        _ => ListView(
          padding: EdgeInsets.only(
            bottom: NexSpacing.md + nexBottomInset(context),
          ),
          children: [
            NexCollectionHero(
              icon: Icons.schedule_send_outlined,
              color: hue,
              count: notes.length,
              title: l10n.scheduledTitle,
              hint: l10n.scheduledSubtitle,
            ),
            for (final note in notes) _card(note, hue),
          ],
        ),
      },
    );
  }

  /// A note on its way (2.3.2): when it arrives and in how many days, when
  /// it was written, and a bar for how much of the wait is behind it.
  Widget _card(ScheduledNote note, Color hue) {
    final l10n = AppLocalizations.of(context);
    final solar = widget.services.solarCalendar;
    final total = note.releaseAt.difference(note.writtenAt).inMinutes;
    final gone = DateTime.now().toUtc().difference(note.writtenAt).inMinutes;
    final days = nexDaysUntil(note.releaseAt.toLocal());
    return NexCollectionTile(
      key: ValueKey('scheduled-${note.id}'),
      leading: NexCollectionSquare(
        icon: Icons.schedule_send_outlined,
        color: hue,
      ),
      title: Text(
        NexMarkdownText.preview(note.content),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      accent: hue,
      progress: total <= 0 ? 1 : (gone / total).clamp(0.0, 1.0),
      meta: [
        NexMetaChip(
          icon: Icons.event_outlined,
          color: hue,
          label: l10n.scheduledArrives(
            nexDueExact(
              context,
              note.releaseAt.toLocal(),
              solarCalendar: solar,
            ),
          ),
        ),
        if (days > 0)
          NexMetaChip(
            icon: Icons.hourglass_bottom,
            label: l10n.scheduledInDays(days),
          ),
        NexMetaChip(
          icon: Icons.edit_outlined,
          label: l10n.scheduledWritten(nexTimeAgo(context, note.writtenAt)),
        ),
      ],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('scheduled-now-${note.id}'),
            tooltip: l10n.scheduledSendNow,
            color: hue,
            icon: const Icon(Icons.send_outlined),
            onPressed: () => unawaited(_sendNow(note)),
          ),
          NexPopupMenuButton<VoidCallback>(
            tooltip: l10n.moreActions,
            onSelected: (run) => run(),
            itemBuilder: (context) => [
              nexMenuItem(
                value: () => unawaited(_changeTime(note)),
                icon: Icons.schedule_outlined,
                label: l10n.scheduledChangeTime,
              ),
              nexMenuItem(
                value: () => unawaited(_discard(note)),
                icon: Icons.delete_outline,
                label: l10n.scheduledDiscard,
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
