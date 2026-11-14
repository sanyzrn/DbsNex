import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import 'choice_cards.dart';
import 'nex_shelf.dart';

/// List or grid: how the home screen lays out the notes (2.6.27).
///
/// One control in two places — Settings → Appearance and the last page of
/// the first run (2.6.28) — each card a small drawing of the layout it
/// chooses, so the choice can be made by looking rather than by reading.
class NexTimelineViewPanel extends StatelessWidget {
  const NexTimelineViewPanel({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NexPanel(
      title: l10n.timelineView,
      icon: Icons.grid_view_rounded,
      child: NexChoiceCards<bool>(
        selected: preferences.timelineGrid,
        onSelected: preferences.setTimelineGrid,
        choices: [
          NexChoice(
            value: false,
            label: l10n.timelineViewList,
            preview: const _ViewPreview(grid: false),
          ),
          NexChoice(
            value: true,
            label: l10n.timelineViewGrid,
            preview: const _ViewPreview(grid: true),
          ),
        ],
      ),
    );
  }
}

/// Three rows of cards, or four tiles in two columns, in the accent's family.
class _ViewPreview extends StatelessWidget {
  const _ViewPreview({required this.grid});

  final bool grid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color tile(String type, {double alpha = 0.22}) => Color.alphaBlend(
      nexNoteTypeTint(type, scheme).withValues(alpha: alpha),
      scheme.surfaceContainerLowest,
    );
    Widget box(String type, {double? height}) => Container(
      height: height,
      decoration: BoxDecoration(
        color: tile(type),
        borderRadius: BorderRadius.circular(NexRadius.xs),
      ),
    );
    const gap = SizedBox.square(dimension: 3);
    return ExcludeSemantics(
      child: SizedBox(
        width: 48,
        height: 36,
        child: grid
            ? Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: box('text')),
                        gap,
                        Expanded(child: box('voice')),
                      ],
                    ),
                  ),
                  gap,
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: box('checklist')),
                        gap,
                        Expanded(child: box('photo')),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(child: box('text')),
                  gap,
                  Expanded(child: box('voice')),
                  gap,
                  Expanded(child: box('checklist')),
                ],
              ),
      ),
    );
  }
}

/// Time, kind or tag: what the home screen's headings are (2.7.0).
///
/// Beside list or grid, and drawn the same way: each card a small picture of
/// the headings it makes — days, a kind's coloured mark, a tag's dot — with
/// one line under the cards saying what the chosen one does.
class NexTimelineArrangementPanel extends StatelessWidget {
  const NexTimelineArrangementPanel({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final by = preferences.timelineArrangement;
    return NexPanel(
      title: l10n.timelineArrange,
      icon: Icons.view_day_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexChoiceCards<NexTimelineArrangement>(
            selected: by,
            onSelected: preferences.setTimelineArrangement,
            choices: [
              for (final value in NexTimelineArrangement.values)
                NexChoice(
                  value: value,
                  label: switch (value) {
                    NexTimelineArrangement.time => l10n.timelineArrangeTime,
                    NexTimelineArrangement.type => l10n.timelineArrangeType,
                    NexTimelineArrangement.tag => l10n.timelineArrangeTag,
                  },
                  preview: NexArrangementPreview(by: value),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            l10n.timelineArrangeHint(by.name),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Two headings and the rows under them, in miniature: a plain bar for a
/// day, a kind's coloured square, a tag's dot.
class NexArrangementPreview extends StatelessWidget {
  const NexArrangementPreview({super.key, required this.by});

  final NexTimelineArrangement by;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color wash(String type) => Color.alphaBlend(
      nexNoteTypeTint(type, scheme).withValues(alpha: 0.22),
      scheme.surfaceContainerLowest,
    );
    Widget mark(int i, String type) => switch (by) {
      NexTimelineArrangement.time => const SizedBox.shrink(),
      NexTimelineArrangement.type => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsetsDirectional.only(end: 3),
        decoration: BoxDecoration(
          color: nexNoteTypeTint(type, scheme),
          borderRadius: BorderRadius.circular(NexRadius.xs),
        ),
      ),
      NexTimelineArrangement.tag => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsetsDirectional.only(end: 3),
        decoration: BoxDecoration(
          color: i == 0 ? scheme.primary : scheme.tertiary,
          shape: BoxShape.circle,
        ),
      ),
    };
    Widget heading(int i, String type) => Row(
      children: [
        mark(i, type),
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(NexRadius.xs),
          ),
        ),
      ],
    );
    Widget row(String type) => Expanded(
      child: Container(
        decoration: BoxDecoration(
          // By day the rows are every kind mixed; on a shelf, all one.
          color: wash(type),
          borderRadius: BorderRadius.circular(NexRadius.xs),
        ),
      ),
    );
    const gap = SizedBox(height: 2);
    final first = by == NexTimelineArrangement.time ? 'voice' : 'text';
    final second = by == NexTimelineArrangement.time ? 'checklist' : 'photo';
    return ExcludeSemantics(
      child: SizedBox(
        width: 48,
        height: 36,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading(0, 'text'),
            gap,
            row('text'),
            gap,
            row(first),
            const SizedBox(height: 3),
            heading(1, 'photo'),
            gap,
            row(second),
            gap,
            row('photo'),
          ],
        ),
      ),
    );
  }
}
