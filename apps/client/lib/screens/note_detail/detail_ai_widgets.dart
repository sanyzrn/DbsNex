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
    );
  }
}
