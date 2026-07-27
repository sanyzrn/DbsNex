import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../tokens/nex_tokens.dart';

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
                onTap: () => onSelected(
                  selectedTagId == tag.id ? null : tag.id,
                ),
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
    final bg = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.surface;
    final fg = selected
        ? theme.colorScheme.surface
        : theme.colorScheme.onSurface;
    Color? dot;
    if (accent != null) {
      dot = Color(int.parse(accent!.substring(1), radix: 16) + 0xFF000000);
      if (selected) dot = fg.withValues(alpha: 0.9);
    }
    return Material(
      color: bg,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? bg : theme.colorScheme.outline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ] else if (!selected) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
