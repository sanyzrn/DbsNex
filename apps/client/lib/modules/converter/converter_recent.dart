import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_history.dart';
import 'converter_outcome.dart';
import 'converter_strings.dart';

/// The conversions this person has already made, for the tab they are on: the
/// starred ones first, then the last few. A tap puts one back in the fields;
/// the menu stars it or takes it away.
class ConverterHistory extends StatelessWidget {
  const ConverterHistory({
    super.key,
    required this.tab,
    required this.recents,
    required this.favorites,
    required this.onOpen,
    required this.onRemove,
    required this.onStar,
  });

  final ConverterTab tab;
  final List<ConverterEntry> recents;
  final List<ConverterEntry> favorites;
  final ValueChanged<ConverterEntry> onOpen;
  final ValueChanged<ConverterEntry> onRemove;
  final void Function(ConverterEntry entry, bool star) onStar;

  @override
  Widget build(BuildContext context) {
    final strings = converterStrings;
    final theme = Theme.of(context);
    final starred = [
      for (final entry in favorites)
        if (entry.tab == tab) entry,
    ].take(5).toList();
    final recent = [
      for (final entry in recents)
        if (entry.tab == tab) entry,
    ].take(5).toList();
    if (starred.isEmpty && recent.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexShelfHeading(
            icon: Icons.history,
            title: strings(context, 'recentTitle'),
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            strings(context, 'emptyRecent'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (starred.isNotEmpty) ...[
          NexShelfHeading(
            icon: Icons.star_outline_rounded,
            title: strings(context, 'favoritesTitle'),
          ),
          const SizedBox(height: NexSpacing.sm),
          _rows(context, starred),
          const SizedBox(height: NexSpacing.md),
        ],
        if (recent.isNotEmpty) ...[
          NexShelfHeading(
            icon: Icons.history,
            title: strings(context, 'recentTitle'),
          ),
          const SizedBox(height: NexSpacing.sm),
          _rows(context, recent),
        ],
      ],
    );
  }

  Widget _rows(BuildContext context, List<ConverterEntry> entries) {
    return Column(
      children: [
        for (final (index, entry) in entries.indexed)
          NexGroupedRow(
            index: index,
            count: entries.length,
            child: _HistoryRow(
              entry: entry,
              onOpen: () => onOpen(entry),
              onRemove: () => onRemove(entry),
              onStar: (star) => onStar(entry, star),
            ),
          ),
      ],
    );
  }
}

enum _HistoryAction { star, unstar, remove }

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.onOpen,
    required this.onRemove,
    required this.onStar,
  });

  final ConverterEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final ValueChanged<bool> onStar;

  @override
  Widget build(BuildContext context) {
    final strings = converterStrings;
    final theme = Theme.of(context);
    // The words are rebuilt in today's language from what the record kept, so
    // a conversion made in English reads in Persian after a language change.
    final label =
        converterOutcomeFromEntry(context, entry)?.label ?? entry.label;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: NexSpacing.md,
          end: NexSpacing.xs,
          top: NexSpacing.xs,
          bottom: NexSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              entry.starred ? Icons.star_rounded : Icons.history,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            NexPopupMenuButton<_HistoryAction>(
              tooltip: strings(context, 'more'),
              icon: Icon(
                Icons.more_vert,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onSelected: (action) {
                switch (action) {
                  case _HistoryAction.star:
                    onStar(true);
                    break;
                  case _HistoryAction.unstar:
                    onStar(false);
                    break;
                  case _HistoryAction.remove:
                    onRemove();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (entry.starred)
                  nexMenuItem(
                    value: _HistoryAction.unstar,
                    icon: Icons.star_outline_rounded,
                    label: strings(context, 'unfavorite'),
                  )
                else
                  nexMenuItem(
                    value: _HistoryAction.star,
                    icon: Icons.star_outline_rounded,
                    label: strings(context, 'favorite'),
                  ),
                nexMenuItem(
                  value: _HistoryAction.remove,
                  icon: Icons.delete_outline,
                  label: strings(context, 'remove'),
                  destructive: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
