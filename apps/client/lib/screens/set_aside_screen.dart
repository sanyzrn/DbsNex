import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/display_date.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/collection_page.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_shelf.dart';

/// The archive: notes off the home screen, not gone (2.3.0 redesign).
///
/// Two runs of cards. "Coming back on their own" holds the notes archived
/// until a time, soonest first, each saying how many days are left; "Waiting
/// for you" holds the ones that stay until they are brought back. A card opens
/// the note (with only the actions an archived note needs); its two buttons
/// bring it back or delete it, each with an Undo.
class SetAsideScreen extends StatefulWidget {
  const SetAsideScreen({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<SetAsideScreen> createState() => _SetAsideScreenState();
}

class _SetAsideScreenState extends State<SetAsideScreen> {
  /// Null until the first read comes back, which is not the same as empty.
  List<Note>? notes;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  Future<void> reload() async {
    final loaded = await widget.services.listSetAside();
    if (!mounted) return;
    // The sheet above these rows closes unchanged more often than not, and
    // its pop transition is the wrong moment to repaint identical cards for
    // a fresh set of the same rows.
    if (notes != null && nexSameNotes(notes!, loaded)) return;
    setState(() => notes = loaded);
  }

  Future<void> _bringBack(Note note) async {
    if (widget.preferences.haptics) unawaited(HapticFeedback.selectionClick());
    // Off the list at once, so the card does not linger after the tap.
    setState(() => notes = [...?notes]..removeWhere((n) => n.id == note.id));
    await widget.services.bringBack(note.id);
    await widget.services.refreshTimeline();
    await reload();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    nexShowBanner(
      context,
      message: l10n.archiveUnarchived,
      haptics: widget.preferences.haptics,
      actionLabel: l10n.undo,
      // Back into the archive until the same time it was waiting for.
      onAction: () async {
        await widget.services.setAside(note.id, until: note.setAsideUntil);
        await widget.services.refreshTimeline();
        await reload();
      },
    );
  }

  /// The menu's two "all" actions ask first, and so need no Undo (2.3.1).
  Future<void> _all(String action) async {
    final all = [...?notes];
    if (all.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final deleting = action == 'delete';
    final ok = await nexConfirmDestructive(
      context,
      title: deleting ? l10n.archiveDeleteAll : l10n.archiveBringBackAll,
      body: deleting
          ? l10n.archiveDeleteAllBody(all.length)
          : l10n.archiveBringBackAllBody(all.length),
      confirm: deleting ? l10n.delete : l10n.setAsideBringBack,
    );
    if (!ok || !mounted) return;
    if (widget.preferences.haptics) unawaited(HapticFeedback.mediumImpact());
    setState(() => notes = const []);
    for (final note in all) {
      if (deleting) {
        await widget.services.deleteNote(note.id);
      } else {
        await widget.services.bringBack(note.id);
      }
    }
    await widget.services.refreshTimeline();
    await reload();
  }

  Future<void> _open(Note note) async {
    await nexOpenNoteFromCollection(
      context,
      services: widget.services,
      preferences: widget.preferences,
      note: note,
    );
    if (mounted) await reload();
  }

  Future<void> _delete(Note note) async {
    setState(() => notes = [...?notes]..removeWhere((n) => n.id == note.id));
    await nexDeleteNoteWithUndo(
      context,
      services: widget.services,
      preferences: widget.preferences,
      note: note,
      onUndone: () => unawaited(reload()),
    );
    if (mounted) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = notes;
    final timed = [
      for (final note in loaded ?? const <Note>[])
        if (note.setAsideUntil != null) note,
    ]..sort((a, b) => a.setAsideUntil!.compareTo(b.setAsideUntil!));
    final waiting = [
      for (final note in loaded ?? const <Note>[])
        if (note.setAsideUntil == null) note,
    ];
    return Scaffold(
      appBar: NexAppBar(
        title: Text(l10n.setAsidePageTitle),
        actions: [
          if (loaded != null && loaded.length > 1)
            NexPopupMenuButton<String>(
              key: const ValueKey('archive-menu'),
              onSelected: (action) => unawaited(_all(action)),
              itemBuilder: (context) => [
                nexMenuItem(
                  value: 'back',
                  icon: Icons.unarchive_outlined,
                  label: l10n.archiveBringBackAll,
                ),
                nexMenuItem(
                  value: 'delete',
                  icon: Icons.delete_outline,
                  label: l10n.archiveDeleteAll,
                  destructive: true,
                ),
              ],
            ),
        ],
      ),
      body: loaded == null
          ? const NexLoadingList()
          : loaded.isEmpty
          ? NexEmptyState(
              icon: Icons.archive_outlined,
              message: '${l10n.setAsideEmptyTitle}\n${l10n.setAsideEmptyBody}',
            )
          : ListView(
              padding: EdgeInsets.only(
                bottom: NexSpacing.md + nexBottomInset(context),
              ),
              children: [
                NexCollectionHero(
                  icon: Icons.archive_outlined,
                  color: NexHue.amber.on(context),
                  count: loaded.length,
                  title: l10n.setAsidePageTitle,
                  hint: l10n.setAsideSheetHint,
                ),
                if (timed.isNotEmpty) ...[
                  NexCollectionSection(
                    label: l10n.archiveComingBack,
                    icon: Icons.schedule,
                  ),
                  for (final note in timed) _card(note, l10n),
                ],
                if (waiting.isNotEmpty) ...[
                  NexCollectionSection(
                    label: l10n.archiveWaiting,
                    icon: Icons.inventory_2_outlined,
                  ),
                  for (final note in waiting) _card(note, l10n),
                ],
              ],
            ),
    );
  }

  Widget _card(Note note, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final persian = l10n.localeName == 'fa';
    final until = note.setAsideUntil;
    final archived = note.setAsideAt;
    return NexCollectionTile(
      key: ValueKey('archive-${note.id}'),
      leading: NexNoteKindSquare(type: note.type),
      title: Text(nexNoteHeadline(note, l10n)),
      accent: nexNoteTypeTint(note.type.wireName, scheme),
      onTap: () => unawaited(_open(note)),
      meta: [
        if (until != null)
          NexMetaChip(
            icon: Icons.event_repeat,
            color: NexHue.amber.on(context),
            label:
                '${l10n.archiveBackIn(nexDaysUntil(until).clamp(0, 9999))} · '
                '${nexReadableDate(until, solar: widget.services.solarCalendar, persian: persian)}',
          ),
        if (archived != null)
          NexMetaChip(
            icon: Icons.archive_outlined,
            label: l10n.archivedAgo(nexTimeAgo(context, archived)),
          ),
        if (note.dueAt != null)
          NexMetaChip(icon: Icons.notifications_none, label: l10n.remind),
      ],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('archive-back-${note.id}'),
            tooltip: l10n.setAsideBringBack,
            color: NexHue.amber.on(context),
            icon: const Icon(Icons.unarchive_outlined),
            onPressed: () => unawaited(_bringBack(note)),
          ),
          IconButton(
            key: ValueKey('archive-delete-${note.id}'),
            tooltip: l10n.delete,
            color: Theme.of(context).colorScheme.error,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(_delete(note)),
          ),
        ],
      ),
    );
  }
}
