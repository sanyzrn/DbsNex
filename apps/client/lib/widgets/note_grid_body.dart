part of 'note_grid_card.dart';

/// As much of the note as the tile has room for.
class _Body extends StatelessWidget {
  const _Body({
    required this.note,
    required this.title,
    required this.body,
    required this.strings,
    required this.tint,
    required this.muted,
    required this.outline,
  });

  final Note note;
  final String title;
  final String body;
  final NexCardStrings strings;
  final Color tint;
  final Color muted;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      height: 1.4,
    );
    final heading = title;
    final uri = note.mediaUri;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final width = constraints.maxWidth;
        // Whole lines only: a line cut through the middle reads as a glitch.
        //
        // Measured, not estimated (2.7.2). The count used to be the height
        // over `fontSize × height`, and a Persian line — Vazirmatn, often
        // with a Latin word in it — lays out taller than that, so the last
        // "whole" line was drawn half under the tile's clip. The lines are
        // laid out here exactly as the Text below will lay them out, and
        // only those that fit completely are kept.
        // With the Text widget's own inputs — the inherited style, the
        // locale that picks the fallback font, the height behaviour — so
        // the count is for the lines it will actually draw.
        final inherited = DefaultTextStyle.of(context).style;
        final locale = Localizations.maybeLocaleOf(context);
        final heightBehavior = DefaultTextHeightBehavior.maybeOf(context);
        List<double> measure(String text, TextStyle? style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: inherited.merge(style)),
            textDirection: nexDirectionOf(text),
            textScaler: scaler,
            locale: locale,
            textHeightBehavior: heightBehavior,
            maxLines: 40,
          )..layout(maxWidth: width);
          final heights = [
            for (final line in painter.computeLineMetrics()) line.height,
          ];
          painter.dispose();
          return heights;
        }

        List<double> linesOf(String text, TextStyle? style) {
          // Remembered across builds (2.7.2): a tile scrolled back into view,
          // or rebuilt for a reason that is not its words, asks the same
          // question again, and laying the text out to answer it was a third
          // of what a tile cost to build on a scrolling grid.
          final key = (text, width, style, scaler, locale);
          final known = _lineHeights[key];
          if (known != null) return known;
          if (_lineHeights.length > 600) _lineHeights.clear();
          return _lineHeights[key] = measure(text, style);
        }

        double lineOf(TextStyle? style) {
          final heights = linesOf('Ag آگ', style);
          return heights.isEmpty
              ? scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.3)
              : heights.first;
        }

        // How many of [text]'s lines fit [height], and the height they take.
        (int, double) fitting(String text, TextStyle? style, double height) {
          var used = 0.0;
          var count = 0;
          for (final line in linesOf(text, style)) {
            if (used + line > height + 0.5) break;
            used += line;
            count++;
          }
          return (count, used);
        }

        int fit(double height, TextStyle? style) =>
            (height / lineOf(style)).floor().clamp(1, 40);
        Widget headingText(int lines) => Text(
          heading,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          textDirection: nexDirectionOf(heading),
          style: titleStyle,
        );

        if (note.type == NoteType.photo && uri != null) {
          final caption = heading.isNotEmpty ? heading : body;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(NexRadius.md),
                  child: Image.file(
                    File(uri),
                    fit: BoxFit.cover,
                    cacheWidth:
                        (constraints.maxWidth *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: tint.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: outline,
                      ),
                    ),
                  ),
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.xs),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: nexDirectionOf(caption),
                  style: bodyStyle?.copyWith(color: scheme.onSurface),
                ),
              ],
            ],
          );
        }

        if (note.type == NoteType.checklist) {
          final items = note.checklistItems
              .where((item) => item.text.trim().isNotEmpty)
              .toList();
          final open = [
            ...items.where((i) => !i.done),
            ...items.where((i) => i.done),
          ];
          final rows = fit(
            constraints.maxHeight - (heading.isEmpty ? 0 : lineOf(titleStyle)),
            bodyStyle,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (heading.isNotEmpty) headingText(1),
              for (final item in open.take(rows))
                Row(
                  children: [
                    Icon(
                      item.done
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 15,
                      color: item.done ? tint : outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: nexDirectionOf(item.text),
                        style: bodyStyle?.copyWith(
                          color: item.done ? muted : scheme.onSurface,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          );
        }

        final extra = switch (note.type) {
          NoteType.voice when (note.durationMs ?? 0) > 0 =>
            strings.durationLabel?.call(note.durationMs!),
          NoteType.link => Uri.tryParse(note.linkUrl ?? '')?.host,
          _ => null,
        };
        final rest = body;
        final restStyle = heading.isEmpty
            ? bodyStyle?.copyWith(color: scheme.onSurface)
            : bodyStyle;
        // The heading takes up to three lines; the words under it every
        // whole line that is left.
        var headLines = 0;
        var headHeight = 0.0;
        if (heading.isNotEmpty) {
          final lines = linesOf(heading, titleStyle);
          for (final line in lines.take(3)) {
            if (headLines > 0 && headHeight + line > constraints.maxHeight) {
              break;
            }
            headHeight += line;
            headLines++;
          }
        }
        final used =
            headHeight +
            (extra == null || extra.isEmpty ? 0 : lineOf(bodyStyle) + 2);
        // A text note's caption sits under its words, quiet, as on the list
        // card — it used to be left off the tile altogether (2.7.2). Up to
        // two lines, and never so many that the note's own words lose their
        // first line to it.
        final caption = note.type == NoteType.text
            ? NexMarkdownText.preview(note.caption ?? '').trim()
            : '';
        const captionGap = NexSpacing.xs;
        var captionLines = 0;
        var captionHeight = 0.0;
        if (caption.isNotEmpty) {
          final room =
              constraints.maxHeight -
              used -
              captionGap -
              (rest.isEmpty ? 0 : lineOf(restStyle));
          final fit = fitting(
            caption,
            bodyStyle,
            math.min(room, lineOf(bodyStyle) * 2 + 1),
          );
          captionLines = fit.$1;
          captionHeight = captionLines == 0 ? 0 : fit.$2 + captionGap;
        }
        final restLines = rest.isEmpty
            ? 0
            : fitting(
                rest,
                restStyle,
                constraints.maxHeight - used - captionHeight,
              ).$1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (heading.isNotEmpty) headingText(headLines),
            if (extra != null && extra.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      note.type == NoteType.voice
                          ? Icons.graphic_eq_rounded
                          : Icons.public_rounded,
                      size: 14,
                      color: tint,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        extra,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (rest.isNotEmpty && restLines > 0)
              Flexible(
                child: Text(
                  rest,
                  maxLines: restLines,
                  overflow: TextOverflow.ellipsis,
                  textDirection: nexDirectionOf(rest),
                  style: restStyle,
                ),
              ),
            if (captionLines > 0) ...[
              const SizedBox(height: captionGap),
              Text(
                caption,
                key: const ValueKey('grid-caption'),
                maxLines: captionLines,
                overflow: TextOverflow.ellipsis,
                textDirection: nexDirectionOf(caption),
                style: bodyStyle,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Line heights already measured, by text, width, style, text scale and
/// locale — see `_Body`'s `linesOf`.
final _lineHeights = <Object, List<double>>{};
