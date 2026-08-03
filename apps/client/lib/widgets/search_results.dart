import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
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
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);

  if (search.query.text.trim().isEmpty && search.activeFilterCount == 0) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Text(l10n.searchStart, style: theme.textTheme.bodyMedium),
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
