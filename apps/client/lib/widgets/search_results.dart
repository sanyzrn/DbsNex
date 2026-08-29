import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/note_search.dart';
import 'card_strings.dart';
import 'search_field_header.dart' show nexSearchTapGroup;

/// Search results as slivers, so they can replace the timeline's cards inside
/// the timeline's own scroll view rather than on a screen of their own.
///
/// Returning slivers rather than a widget is the whole reason search no longer
/// needs a route: the query field stays pinned where it was typed into, and the
/// list under it simply becomes the answer.
List<Widget> searchResultSlivers({
  required BuildContext context,
  required NoteSearchController search,
  required ValueChanged<Note> onOpen,
  NexPreferences? preferences,
  ValueChanged<String>? onUseSaved,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);

  if (search.query.text.trim().isEmpty && search.activeFilterCount == 0) {
    final saved = preferences?.savedSearches ?? const <String>[];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.searchStart, style: theme.textTheme.bodyMedium),
              // Kept searches live here rather than behind a menu: the empty
              // search screen is the one moment they are useful, and it is
              // otherwise a screen with a sentence on it.
              if (saved.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.lg),
                Text(l10n.savedSearches, style: theme.textTheme.titleSmall),
                const SizedBox(height: NexSpacing.sm),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final query in saved)
                      InputChip(
                        label: Text(query),
                        onPressed: () => onUseSaved?.call(query),
                        onDeleted: () =>
                            unawaited(preferences!.removeSavedSearch(query)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  /// Offered above the results, and only when there is something to keep that
  /// is not kept already — a button that saves what is already saved is a
  /// button that teaches people it does nothing.
  Widget? saveAction() {
    final query = search.query.text.trim();
    if (preferences == null || query.isEmpty) return null;
    if (preferences.savedSearches.contains(query)) return null;
    return SliverToBoxAdapter(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
          child: TextButton.icon(
            onPressed: () => unawaited(preferences.saveSearch(query)),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(l10n.saveSearch),
          ),
        ),
      ),
    );
  }

  // Before "no results": a search that threw found nothing in the sense that
  // matters here, and saying "nothing matches" would blame the query for the
  // database's problem.
  if (search.failure != null) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.searchFailed, style: theme.textTheme.bodyMedium),
              const SizedBox(height: NexSpacing.sm),
              // The one thing worth offering. A search is cheap and the
              // failure may not repeat, so the way out is to ask again rather
              // than to leave search altogether — which was the only way out
              // before.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => unawaited(search.run()),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.retry),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  if (!search.hasRun) {
    return [
      SliverList.builder(
        itemCount: 3,
        itemBuilder: (_, __) => const NexCardSkeleton(),
      ),
    ];
  }

  if (search.results.isEmpty) {
    final hasSemantic = search.semanticResults.isNotEmpty;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.nothingMatches(search.query.text),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: NexSpacing.lg),
              // The nearest miss is the point of this state: an empty result
              // that shows the closest thing you actually wrote is a different
              // experience from one that says "no results".
              if (search.nearest != null) ...[
                Text(l10n.closestThing, style: theme.textTheme.bodySmall),
                const SizedBox(height: NexSpacing.sm),
              ] else if (!hasSemantic)
                Text(l10n.nothingClose, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
      if (search.nearest != null)
        SliverToBoxAdapter(
          child: TapRegion(
            groupId: nexSearchTapGroup,
            child: NoteCard(
              note: search.nearest!,
              strings: nexCardStrings(context),
              onTap: () => onOpen(search.nearest!),
            ),
          ),
        ),
      // Nothing shares a word with the query, but these share its meaning —
      // a keyword index can never surface them, only an embedding can.
      if (hasSemantic) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.lg,
              NexSpacing.md,
              NexSpacing.lg,
              NexSpacing.sm,
            ),
            child: Text(l10n.semanticMatches, style: theme.textTheme.bodySmall),
          ),
        ),
        SliverList.builder(
          itemCount: search.semanticResults.length,
          itemBuilder: (context, index) {
            final note = search.semanticResults[index];
            return TapRegion(
              groupId: nexSearchTapGroup,
              child: NoteCard(
                note: note,
                strings: nexCardStrings(context),
                onTap: () => onOpen(note),
              ),
            );
          },
        ),
      ],
    ];
  }

  return [
    if (saveAction() case final action?) action,
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NexSpacing.md,
          NexSpacing.sm,
          NexSpacing.md,
          NexSpacing.sm,
        ),
        child: Text(
          l10n.resultCount(search.results.length),
          style: theme.textTheme.bodySmall,
        ),
      ),
    ),
    SliverList.builder(
      itemCount: search.results.length,
      itemBuilder: (context, index) {
        final note = search.results[index];
        return TapRegion(
          groupId: nexSearchTapGroup,
          child: NoteCard(
            note: note,
            strings: nexCardStrings(context),
            onTap: () => onOpen(note),
          ),
        );
      },
    ),
  ];
}
