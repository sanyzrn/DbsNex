import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'nex_dialog.dart';
import '../platform/note_search.dart';

/// The search filter sheet: tags, note types and a date window.
///
/// The controller has carried a tag set, a type set and a date range since
/// search moved onto the timeline — the parser even documents that "the filter
/// row can express the first two by tapping" — but nothing in the UI ever
/// wrote to them, so the only way to filter was typing `tag:` and `type:`
/// operators into the field, a syntax documented once, in the tour. This
/// sheet is the tapping.
///
/// Chips apply immediately (the controller re-runs the debounced search), the
/// sheet stays open underneath so several can be combined — that is what
/// "filters" means; a picker that closes after one choice is a picker.
Future<void> nexShowSearchFilterSheet(
  BuildContext context, {
  required NoteSearchController search,
}) => nexShowSheet(
  context: context,
  builder: (context) => _SearchFilterSheet(search: search),
);

class _SearchFilterSheet extends StatelessWidget {
  const _SearchFilterSheet({required this.search});

  final NoteSearchController search;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: search,
      builder: (context, _) {
        final active = search.activeFilterCount;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.lg,
            NexSpacing.sm,
            NexSpacing.lg,
            NexSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.searchFilters,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (active > 0)
                    TextButton(
                      onPressed: search.clearFilters,
                      child: Text(l10n.searchFiltersClear(active)),
                    ),
                ],
              ),
              const SizedBox(height: NexSpacing.sm),
              if (search.allTags.isNotEmpty) ...[
                Text(
                  l10n.searchFilterTags,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: NexSpacing.xs),
                Wrap(
                  spacing: NexSpacing.xs,
                  runSpacing: NexSpacing.xs,
                  children: [
                    for (final tag in search.allTags)
                      FilterChip(
                        label: Text(tag.name),
                        selected: search.tags.contains(tag.id),
                        onSelected: (_) => search.toggleTag(tag.id),
                      ),
                  ],
                ),
                const SizedBox(height: NexSpacing.md),
              ],
              Text(
                l10n.searchFilterTypes,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: NexSpacing.xs),
              Wrap(
                spacing: NexSpacing.xs,
                runSpacing: NexSpacing.xs,
                children: [
                  for (final type in NoteType.values)
                    FilterChip(
                      label: Text(l10n.noteType(type.wireName)),
                      selected: search.types.contains(type),
                      onSelected: (_) => search.toggleType(type),
                    ),
                ],
              ),
              const SizedBox(height: NexSpacing.md),
              Text(
                l10n.searchFilterDates,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: NexSpacing.xs),
              Wrap(
                spacing: NexSpacing.xs,
                runSpacing: NexSpacing.xs,
                children: [
                  for (final preset in NoteDatePreset.values)
                    ChoiceChip(
                      label: Text(switch (preset) {
                        NoteDatePreset.any => l10n.searchFilterAnyTime,
                        NoteDatePreset.today => l10n.searchFilterToday,
                        NoteDatePreset.last7Days => l10n.searchFilterLast7Days,
                        NoteDatePreset.last30Days =>
                          l10n.searchFilterLast30Days,
                      }),
                      selected: search.datePreset == preset,
                      onSelected: (_) => search.setDatePreset(preset),
                    ),
                ],
              ),
              // The scrim gap under a sheet the keyboard can close into is
              // handled by nexShowSheet; this row keeps the accent visible so
              // the sheet reads as finished, not truncated.
              const SizedBox(height: NexSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      active == 0
                          ? l10n.searchFiltersHint
                          : l10n.searchFiltersActive(active),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
