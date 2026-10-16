part of '../note_detail_sheet.dart';

class _AiResult {
  const _AiResult(this.id, this.label, this.text);
  final String id;
  final String label;
  final String text;
}

/// A visible action in the note's AI workspace, with the label in normal
/// reading ink and only the glyph in the accent. Wrap handles narrow screens
/// and large text without shrinking the tap target or clipping the name.
class _AiActionPill extends StatelessWidget {
  const _AiActionPill({required this.action});
  final _DetailAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return OutlinedButton.icon(
      key: ValueKey('note-ai-action-${action.icon?.codePoint ?? 'summary'}'),
      onPressed: action.onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        disabledForegroundColor: theme.disabledColor,
        backgroundColor: scheme.primary.withValues(alpha: 0.05),
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: theme.textTheme.labelLarge,
      ),
      icon: IconTheme.merge(
        data: IconThemeData(
          size: 18,
          color: action.onPressed == null
              ? theme.disabledColor
              : scheme.primary,
        ),
        child: action.glyph ?? Icon(action.icon, size: 18),
      ),
      label: Text(action.label),
    );
  }
}
