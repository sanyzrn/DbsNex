import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../tokens/nex_tokens.dart';
import 'nex_tappable.dart';

/// Horizontally scrolling tag filter pills (mockup `.filter-row` / FR-4).
///
/// "All" is active when [selectedTagId] is null. Each tag shows its accent dot.
class TagFilterRow extends StatelessWidget {
  const TagFilterRow({
    super.key,
    required this.tags,
    required this.selectedTagId,
    required this.onSelected,
    this.showAll = true,
    this.allLabel = 'All',
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      NexSpacing.md,
      NexSpacing.md,
      NexSpacing.md,
      NexSpacing.sm,
    ),
  });

  final List<Tag> tags;
  final String? selectedTagId;
  final ValueChanged<String?> onSelected;
  final bool showAll;

  /// Label of the "clear the filter" pill. The design system carries no
  /// localizations of its own, so the app passes the translated string in —
  /// otherwise this pill stayed English in a Persian UI.
  final String allLabel;

  /// Sits before the "All" pill — the mockup's icon button, which opens the
  /// filters that are not tags.
  final Widget? leading;

  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          if (leading != null)
            Padding(
              padding: const EdgeInsets.only(right: NexSpacing.sm),
              child: leading,
            ),
          if (showAll)
            Padding(
              padding: const EdgeInsets.only(right: NexSpacing.sm),
              child: _Pill(
                label: allLabel,
                selected: selectedTagId == null,
                onTap: () => onSelected(null),
                theme: theme,
              ),
            ),
          for (final tag in tags)
            Padding(
              padding: const EdgeInsets.only(right: NexSpacing.sm),
              child: _Pill(
                label: tag.name,
                selected: selectedTagId == tag.id,
                accent: tag.color,
                onTap: () =>
                    onSelected(selectedTagId == tag.id ? null : tag.id),
                theme: theme,
              ),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;
  final String? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    // Selection is the accent's job now. It used to invert to near-black,
    // which reads as "disabled" or "inverted" rather than "this is the filter
    // you are looking through" — and left the app with no way at all to say
    // that something is active.
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.surfaceContainerLowest;
    final fg = selected ? scheme.primary : scheme.onSurface;
    // A tag with no colour used to get a grey dot, which reads as a broken
    // swatch rather than as an absence.
    final dot = accent == null ? null : nexParseTagColor(accent);
    return NexTappable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      shape: const StadiumBorder(),
      child: Material(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? scheme.primary : scheme.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: NexSpacing.sm),
              ],
              Text(
                label,
                // Through the theme, so the most-used control on the timeline
                // is not the one thing typeset outside the design system — and
                // so it follows the app's face rather than the platform's.
                style: theme.textTheme.labelLarge?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
