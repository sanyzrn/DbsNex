import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../widgets/nex_dialog.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(_purgeThenLoad());
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
    setState(() => notes = loaded);
  }

  void _tick() {
    if (widget.preferences?.haptics ?? true) HapticFeedback.selectionClick();
  }

  Future<void> _restore(Note note) async {
    _tick();
    await widget.services.undelete(note.id);
    await widget.services.refreshTimeline();
    await reload();
  }

  Future<void> _purge(Note note) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      title: l10n.deleteForever,
      body: l10n.deleteForeverBody,
      confirm: l10n.delete,
    );
    if (ok != true) return;
    if (widget.preferences?.haptics ?? true) HapticFeedback.mediumImpact();
    await widget.services.purgeNote(note.id);
    await reload();
  }

  Future<void> _emptyTrash() async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      title: l10n.emptyTrash,
      body: l10n.emptyTrashBody(notes?.length ?? 0),
      confirm: l10n.emptyTrash,
    );
    if (ok != true) return;
    if (widget.preferences?.haptics ?? true) HapticFeedback.mediumImpact();
    await widget.services.purgeAllDeleted();
    await reload();
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirm,
  }) {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: NexDialogBody(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(confirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final loaded = notes;
    return Scaffold(
      appBar: AppBar(
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NexSpacing.md,
                    NexSpacing.sm,
                    NexSpacing.md,
                    NexSpacing.xs,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.trashRetention,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.only(bottom: nexBottomInset(context)),
                    itemCount: loaded.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final note = loaded[index];
                      return ListTile(
                        minTileHeight: 56,
                        leading: Icon(nexNoteTypeIcon(note.type.wireName)),
                        title: Text(
                          note.searchableDerivedText?.trim().isNotEmpty == true
                              ? note.searchableDerivedText!
                              : l10n.noteType(note.type.wireName),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: note.deletedAt == null
                            ? null
                            : Text(l10n.noteType(note.type.wireName)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => unawaited(_restore(note)),
                              child: Text(l10n.restore),
                            ),
                            IconButton(
                              tooltip: l10n.deleteForever,
                              color: theme.colorScheme.error,
                              onPressed: () => unawaited(_purge(note)),
                              icon: const Icon(Icons.delete_forever_outlined),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
