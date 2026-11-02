part of '../note_detail_sheet.dart';

class _AiResult {
  const _AiResult(this.id, this.label, this.text);
  final String id;
  final String label;
  final String text;
}

/// One thing Nex AI can do with a note. [resultId] names the result it
/// fills, when what it makes is kept.
class _AiTool {
  const _AiTool({
    required this.label,
    required this.onRun,
    this.icon,
    this.glyph,
    this.resultId,
    this.running = false,
  });

  final String label;
  final IconData? icon;
  final Widget? glyph;
  final String? resultId;
  final bool running;
  final VoidCallback? onRun;
}

/// Short names and icons for the results, shared by the tool row and the
/// result card.
abstract final class _AiResultTabs {
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

  static IconData icon(_AiResult result) => switch (result.id) {
    'translation' => Icons.translate,
    'summary' => Icons.auto_awesome_outlined,
    'image' => Icons.image_outlined,
    'transcript' => Icons.graphic_eq,
    _ when result.id.endsWith('-transcript') => Icons.graphic_eq,
    _ when result.id.endsWith('-image') => Icons.image_outlined,
    _ => Icons.notes_outlined,
  };
}

/// A tool as a round icon (2.3.4): the icon says what it does and a long
/// press its name. A tool with a kept result wears a small check and, chosen,
/// the accent ring; while it works its icon turns into a small spinner.
class _AiToolChip extends StatelessWidget {
  const _AiToolChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.glyph,
    this.running = false,
    this.done = false,
    this.selected = false,
    this.tooltip,
  });

  final String label;

  /// The full name, when [label] is the short one.
  final String? tooltip;
  final IconData? icon;
  final Widget? glyph;
  final bool running;
  final bool done;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? label,
      preferBelow: false,
      excludeFromSemantics: true,
      child: NexTappable(
        selected: selected,
        semanticLabel: tooltip ?? label,
        shape: const CircleBorder(),
        onTap: onTap ?? () {},
        child: SizedBox.square(
          dimension: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: AnimatedContainer(
                  duration: NexMotion.of(context, NexMotion.standard),
                  curve: NexMotion.curve,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? scheme.primary.withValues(alpha: 0.18)
                        : done
                        ? scheme.primary.withValues(alpha: 0.08)
                        : scheme.surfaceContainerLowest,
                    border: Border.all(
                      width: selected ? 1.5 : 1,
                      color: selected
                          ? scheme.primary.withValues(alpha: 0.6)
                          : scheme.outlineVariant,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: SizedBox.square(
                    dimension: 22,
                    child: running
                        ? Padding(
                            padding: const EdgeInsets.all(3),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          )
                        : IconTheme.merge(
                            data: IconThemeData(
                              size: 22,
                              color: scheme.primary,
                            ),
                            child: glyph ?? Icon(icon),
                          ),
                  ),
                ),
              ),
              if (done && !running)
                PositionedDirectional(
                  end: -1,
                  bottom: -1,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.surfaceContainerLow,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The surface a result sits on inside the workspace.
class _AiCard extends StatelessWidget {
  const _AiCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(NexRadius.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

/// One kept result: what it is, its text — a few lines, or all of it — and
/// what can be done with it.
class _AiResultCard extends StatelessWidget {
  const _AiResultCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.expanded,
    required this.onExpand,
    required this.onCopy,
    this.onAgain,
    this.onCaption,
    this.captionBusy = false,
    this.captionKey,
    this.summary = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onCopy;
  final VoidCallback? onAgain;
  final VoidCallback? onCaption;
  final bool captionBusy;
  final Key? captionKey;
  final bool summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.65);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Whether there is more than the preview shows (2.3.4): a result of
        // three lines has nothing to open, and an arrow there does nothing.
        final measure =
            TextPainter(
              text: TextSpan(
                text: summary ? NexMarkdownText.preview(text) : text,
                style: style,
              ),
              maxLines: _previewLines,
              textDirection: nexDirectionOf(text) ?? Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(
              maxWidth: math.max(0, constraints.maxWidth - 2 * NexSpacing.md),
            );
        final long = measure.didExceedMaxLines;
        measure.dispose();
        return _card(context, l10n, theme, scheme, style, long);
      },
    );
  }

  static const _previewLines = 4;

  Widget _card(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme scheme,
    TextStyle? style,
    bool long,
  ) {
    return _AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
              if (onAgain case final again?)
                IconButton(
                  key: const ValueKey('note-ai-again'),
                  tooltip: l10n.aiRunAgain,
                  visualDensity: VisualDensity.compact,
                  onPressed: again,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              if (long)
                IconButton(
                  tooltip: expanded
                      ? l10n.aiResultCollapse
                      : l10n.aiResultExpand,
                  visualDensity: VisualDensity.compact,
                  onPressed: onExpand,
                  icon: AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: NexMotion.of(context, NexMotion.standard),
                    curve: NexMotion.curve,
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.xs),
          if (summary && (expanded || !long))
            NexMarkdown(text, selectable: false, style: style)
          else if (expanded && long)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                primary: false,
                child: NexTextSurface(text, selectable: true, style: style),
              ),
            )
          else
            GestureDetector(
              onTap: long ? onExpand : null,
              child: NexTextSurface(
                summary ? NexMarkdownText.preview(text) : text,
                maxLines: long ? _previewLines : null,
                selectable: !long,
                style: style,
              ),
            ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.xs,
            runSpacing: NexSpacing.xs,
            children: [
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(l10n.copy),
              ),
              if (onCaption case final caption?)
                TextButton.icon(
                  key: captionKey,
                  onPressed: captionBusy ? null : caption,
                  icon: const Icon(Icons.playlist_add_outlined, size: 18),
                  label: Text(l10n.aiAddToCaption),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
