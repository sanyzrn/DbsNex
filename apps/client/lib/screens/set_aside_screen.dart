import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/display_date.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_shelf.dart';
import 'note_detail_sheet.dart';

/// The notes put to one side: off the home screen, not gone.
///
/// Each row says when its note comes back (or that it waits for a hand), opens
/// the note on a tap, and brings it back on the button. A note that has been
/// set aside until a date shows that date, so "when will I see this again" is
/// never a guess.
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
    setState(() => notes = loaded);
  }

  Future<void> _bringBack(Note note) async {
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
    await widget.services.bringBack(note.id);
    await widget.services.refreshTimeline();
    await reload();
  }

  Future<void> _open(Note note) async {
    await nexShowSheet<DetailResult>(
      context: context,
      builder: (_) => NoteDetailSheet(
        services: widget.services,
        preferences: widget.preferences,
        noteId: note.id,
        initialNote: note,
      ),
    );
    await widget.services.refreshTimeline();
    if (mounted) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final persian = l10n.localeName == 'fa';
    final solar = widget.services.solarCalendar;
    final loaded = notes;
    return Scaffold(
      appBar: NexAppBar(title: Text(l10n.setAsidePageTitle)),
      body: loaded == null
          ? const NexLoadingList()
          : loaded.isEmpty
          ? NexEmptyState(
              icon: Icons.archive_outlined,
              message: '${l10n.setAsideEmptyTitle}\n${l10n.setAsideEmptyBody}',
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
                      l10n.setAsideSectionHint,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      NexSpacing.md,
                      0,
                      NexSpacing.md,
                      NexSpacing.md + nexBottomInset(context),
                    ),
                    itemCount: loaded.length,
                    itemBuilder: (context, index) {
                      final note = loaded[index];
                      final until = note.setAsideUntil;
                      final text = note.searchableDerivedText?.trim() ?? '';
                      return NexGroupedRow(
                        index: index,
                        count: loaded.length,
                        child: ListTile(
                          minTileHeight: 56,
                          onTap: () => unawaited(_open(note)),
                          leading: NexIconTile(
                            nexNoteTypeIcon(note.type.wireName),
                          ),
                          title: Text(
                            text.isNotEmpty
                                ? text
                                : l10n.noteType(note.type.wireName),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            until == null
                                ? l10n.setAsideUntilFurther
                                : l10n.setAsideBackOn(
                                    nexReadableDate(
                                      until,
                                      solar: solar,
                                      persian: persian,
                                    ),
                                  ),
                          ),
                          trailing: TextButton(
                            onPressed: () => unawaited(_bringBack(note)),
                            child: Text(l10n.setAsideBringBack),
                          ),
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
