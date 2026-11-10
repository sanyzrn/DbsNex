import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../widgets/collection_page.dart';
import '../l10n/app_localizations.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_shelf.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';

/// The trash.
///
/// Restoring was the only thing it could do: a note stayed until the 30-day
/// purge caught it, with no way to delete one on the spot or to empty the bin.
class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({
    super.key,
    required this.services,
    this.preferences,
  });

  // Takes the service facade, not LibraryMaintenance: maintenance runs inside
  // the database isolate and the UI cannot hold an instance of it.
  final NexServices services;
  final NexPreferences? preferences;

  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  /// Null until the first read comes back — see the tag manager's own field
  /// for why that is not the same as empty. It matters more here than
  /// anywhere: this screen holds the user's deleted notes, so "there is
  /// nothing here" is the one sentence they least want to read by mistake,
  /// and a purge runs before the read that produces it.
  List<Note>? notes;

  /// A permanent deletion waits for its actual Undo window, including holds
  /// and accessibility timing. Null means no overlay was available.
  final _purging = <String, NexBannerHandle?>{};

  Future<void> _finishPurge(String id) async {
    if (!_purging.containsKey(id)) return;
    _purging.remove(id);
    try {
      await widget.services.purgeNote(id);
    } catch (_) {
      // A failed deletion stays in the trash and can be retried.
      if (mounted) {
        await reload();
        if (!mounted) return;
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).operationFailed,
          kind: NexBannerKind.failed,
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_purgeThenLoad());
  }

  @override
  void dispose() {
    for (final handle in _purging.values.toList()) {
      handle?.hide();
    }
    for (final id in _purging.keys.toList()) {
      unawaited(_finishPurge(id));
    }
    super.dispose();
  }

  Future<void> _purgeThenLoad() async {
    await widget.services.purgeDeletedBefore(
      DateTime.now().subtract(const Duration(days: 30)),
    );
    await reload();
  }

  Future<void> reload() async {
    final loaded = await widget.services.deletedNotes();
    if (!mounted) return;
    setState(
      () => notes = [
        for (final note in loaded)
          if (!_purging.containsKey(note.id)) note,
      ],
    );
  }

  void _tick() {
    if (widget.preferences?.haptics ?? true) HapticFeedback.selectionClick();
  }

  Future<void> _restore(Note note) async {
    _tick();
    // Off the list at once, so the card does not linger after the tap.
    setState(() => notes = [...?notes]..removeWhere((n) => n.id == note.id));
    await widget.services.undelete(note.id);
    await widget.services.refreshTimeline();
    await reload();
    if (!mounted) return;
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).trashRestored,
      haptics: widget.preferences?.haptics ?? true,
      actionLabel: AppLocalizations.of(context).undo,
      onAction: () async {
        await widget.services.deleteNote(note.id);
        await widget.services.refreshTimeline();
        await reload();
      },
    );
  }

  /// Deleted for good — after the Undo has had its moment (see [_purging]).
  void _purge(Note note) {
    if (widget.preferences?.haptics ?? true) {
      unawaited(HapticFeedback.mediumImpact());
    }
    setState(() => notes = [...?notes]..removeWhere((n) => n.id == note.id));
    _purging[note.id] = null;
    final l10n = AppLocalizations.of(context);
    final handle = nexShowBanner(
      context,
      message: l10n.trashDeletedForever,
      haptics: widget.preferences?.haptics ?? true,
      actionLabel: l10n.undo,
      onAction: () {
        _purging.remove(note.id);
        unawaited(reload());
      },
    );
    if (handle?.closed case final closed?) {
      _purging[note.id] = handle;
      unawaited(closed.then((_) => _finishPurge(note.id)));
    } else {
      _purging.remove(note.id);
      unawaited(reload());
    }
  }

  Future<void> _emptyTrash() async {
    final l10n = AppLocalizations.of(context);
    final ok = await nexConfirmDestructive(
      context,
      title: l10n.emptyTrash,
      body: l10n.emptyTrashBody(notes?.length ?? 0),
      confirm: l10n.emptyTrash,
    );
    if (!ok) return;
    if (widget.preferences?.haptics ?? true) {
      unawaited(HapticFeedback.mediumImpact());
    }
    for (final handle in _purging.values.toList()) {
      handle?.hide();
    }
    _purging.clear();
    await widget.services.purgeAllDeleted();
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final loaded = notes;
    return Scaffold(
      appBar: NexAppBar(
        title: Text(l10n.trash),
        actions: [
          // Not while the read is still out: an Empty trash button on a
          // screen that has not counted anything yet offers to destroy an
          // unknown number of notes.
          if (loaded != null && loaded.isNotEmpty)
            TextButton(
              onPressed: () => unawaited(_emptyTrash()),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(l10n.emptyTrash),
            ),
        ],
      ),
      body: loaded == null
          ? const NexLoadingList()
          : loaded.isEmpty
          ? NexEmptyState(
              icon: Icons.delete_outline,
              message: l10n.recentlyDeletedEmpty,
            )
          : ListView(
              padding: EdgeInsets.only(
                bottom: NexSpacing.md + nexBottomInset(context),
              ),
              children: [
                NexCollectionHero(
                  icon: Icons.delete_outline,
                  color: NexHue.rose.on(context),
                  count: loaded.length,
                  title: l10n.trash,
                  hint: l10n.trashRetention,
                ),
                for (final note in loaded) _card(note, l10n),
              ],
            ),
    );
  }

  /// How long the trash keeps a note.
  static const _keep = 30;

  Widget _card(Note note, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final deleted = note.deletedAt;
    final left = deleted == null
        ? _keep
        : (_keep + nexDaysUntil(deleted)).clamp(0, _keep);
    return NexCollectionTile(
      key: ValueKey('trash-${note.id}'),
      leading: NexNoteKindSquare(type: note.type),
      title: Text(nexNoteHeadline(note, l10n)),
      accent: left <= 3 ? scheme.error : scheme.outline,
      // The thirty days, running out: a full bar on the day it went in.
      progress: left / _keep,
      meta: [
        if (deleted != null)
          NexMetaChip(
            icon: Icons.delete_outline,
            // The one fact a trash screen exists to convey: *when* this went
            // in — and, now, when it goes for good.
            label: l10n.deletedWhen(nexTimeAgo(context, deleted)),
          ),
        NexMetaChip(
          icon: Icons.hourglass_bottom,
          color: left <= 3 ? scheme.error : null,
          label: l10n.trashGoneIn(left),
        ),
      ],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('trash-restore-${note.id}'),
            tooltip: l10n.restore,
            color: NexHue.rose.on(context),
            icon: const Icon(Icons.restore),
            onPressed: () => unawaited(_restore(note)),
          ),
          IconButton(
            tooltip: l10n.deleteForever,
            color: scheme.error,
            key: ValueKey('trash-purge-${note.id}'),
            onPressed: () => _purge(note),
            icon: const Icon(Icons.delete_forever_outlined),
          ),
        ],
      ),
    );
  }
}
