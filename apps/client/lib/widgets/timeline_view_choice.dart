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
