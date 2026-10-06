import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_services.dart';
import '../widgets/due_label.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_dialog.dart';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scheduledTitle)),
      body: SafeArea(
        child: switch (notes) {
          null => const Center(child: CircularProgressIndicator()),
          [] => NexEmptyState(
            icon: Icons.schedule_send_outlined,
            message: l10n.scheduledEmpty,
          ),
          _ => ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.md,
              NexSpacing.xs,
              NexSpacing.md,
              NexSpacing.lg,
            ),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: NexSpacing.sm),
            itemBuilder: (context, index) => _ScheduledCard(
              note: notes[index],
              solarCalendar: widget.services.solarCalendar,
              onSendNow: () => unawaited(_sendNow(notes[index])),
              onChangeTime: () => unawaited(_changeTime(notes[index])),
              onDiscard: () => unawaited(_discard(notes[index])),
            ),
          ),
        },
      ),
    );
  }
}

class _ScheduledCard extends StatelessWidget {
  const _ScheduledCard({
    required this.note,
    required this.solarCalendar,
    required this.onSendNow,
    required this.onChangeTime,
    required this.onDiscard,
  });

  final ScheduledNote note;
  final bool solarCalendar;
  final VoidCallback onSendNow;
  final VoidCallback onChangeTime;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String exact(DateTime at) =>
        nexDueExact(context, at.toLocal(), solarCalendar: solarCalendar);
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          NexSpacing.md,
          NexSpacing.sm,
          NexSpacing.xs,
          NexSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.schedule_send_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.scheduledArrives(exact(note.releaseAt)),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                PopupMenuButton<VoidCallback>(
                  tooltip: l10n.moreActions,
                  onSelected: (run) => run(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: onSendNow,
                      child: Text(l10n.scheduledSendNow),
                    ),
                    PopupMenuItem(
                      value: onChangeTime,
                      child: Text(l10n.scheduledChangeTime),
                    ),
                    PopupMenuItem(
                      value: onDiscard,
                      child: Text(
                        l10n.scheduledDiscard,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
              child: Text(
                NexMarkdownText.preview(note.content),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              l10n.scheduledWritten(exact(note.writtenAt)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
