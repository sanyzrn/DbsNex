part of '../note_detail_sheet.dart';

class _AiResult {
  const _AiResult(this.id, this.label, this.text);
  final String id;
  final String label;
  final String text;
}

/// Compact AI tools use the same long-press labels as other icon controls.
class _AiActionIcon extends StatelessWidget {
  const _AiActionIcon({required this.action});
  final _DetailAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      key: ValueKey('note-ai-action-${action.icon?.codePoint ?? 'summary'}'),
      message: action.label,
      preferBelow: false,
      child: NexPress(
        enabled: action.onPressed != null,
        child: IconButton.filledTonal(
          onPressed: action.onPressed,
          style: IconButton.styleFrom(
            foregroundColor: scheme.primary,
            disabledForegroundColor: theme.disabledColor,
            backgroundColor: scheme.primary.withValues(alpha: 0.06),
            fixedSize: const Size.square(48),
            shape: const CircleBorder(),
          ),
          icon: action.glyph ?? Icon(action.icon, size: 22),
        ),
      ),
    );
  }
}

/// Direct, compact choices; the full result name stays available to readers.
class _AiResultTabs extends StatelessWidget {
  const _AiResultTabs({
    required this.choices,
    required this.selected,
    required this.onSelected,
  });
  final List<_AiResult> choices;
  final String? selected;
  final ValueChanged<String> onSelected;
  static String label(_AiResult result, AppLocalizations l10n) {
    if (result.id == 'image') return l10n.aiResultImageTab;
    if (result.id == 'extracted') return l10n.aiResultTextTab;
    if (result.id.startsWith('attachment-')) {
      final number = result.label.split(' · ').last;
      final name = result.label.startsWith(l10n.aiImageResult)
          ? l10n.aiResultImageTab
          : result.id.endsWith('-transcript')
          ? l10n.transcript
          : l10n.aiResultTextTab;
      return '$name · $number';
    }
    return result.label;
  }

  IconData _icon(_AiResult result) => switch (result.id) {
    'translation' => Icons.translate,
    'summary' => Icons.auto_awesome_outlined,
    'image' => Icons.image_outlined,
    'transcript' => Icons.graphic_eq,
    _ => Icons.notes_outlined,
  };
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      key: const ValueKey('note-ai-result-picker'),
      spacing: NexSpacing.sm,
      runSpacing: NexSpacing.xs,
      children: [
        for (final result in choices)
          Tooltip(
            message: result.label,
            child: NexTappable(
              key: ValueKey('note-ai-tab-${result.id}'),
              selected: result.id == selected,
              semanticLabel: result.label,
              shape: const StadiumBorder(),
              onTap: () => onSelected(result.id),
              child: AnimatedContainer(
                duration: NexMotion.of(context, NexMotion.standard),
                curve: NexMotion.curve,
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: NexSpacing.md,
                  vertical: NexSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: result.id == selected
                      ? scheme.primary.withValues(alpha: .1)
                      : scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(NexRadius.pill),
                  border: Border.all(
                    color: result.id == selected
                        ? scheme.primary.withValues(alpha: .3)
                        : scheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _icon(result),
                      size: 16,
                      color: result.id == selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: NexSpacing.xs),
                    Flexible(
                      child: Text(
                        label(result, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: result.id == selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
