part of '../note_detail_sheet.dart';

/// A snippet's reading body: one fixed-width block, its language, and the
/// copy action that copies the code and nothing around it.
extension _DetailSnippet on _NoteDetailSheetState {
  Widget _snippetBody(
    BuildContext context,
    NexCodeSnippet snippet,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier New', 'monospace'],
      height: 1.55,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                nexCodeLanguageLabel(
                  context,
                  snippet.language,
                  rawLanguage: snippet.rawLanguage,
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => unawaited(nexCopy(context, snippet.code)),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: Text(l10n.copyCode),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(NexSpacing.sm),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(NexRadius.md),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: NexCodeText(
              snippet.code,
              language: snippet.language,
              style: mono,
              softWrap: false,
            ),
          ),
        ),
      ],
    );
  }
}
