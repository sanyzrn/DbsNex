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
    this.onToggleItem,
  });

  final Note note;
  final String title;
  final String body;
  final NexCardStrings strings;
  final Color tint;
  final Color muted;
  final Color outline;
  final ValueChanged<int>? onToggleItem;

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
          // Each item keeps its place in the list: that place is what a tick
          // is told, whatever order the tile shows them in.
          final items = [
            for (final (i, item) in note.checklistItems.indexed)
              if (item.text.trim().isNotEmpty) (index: i, item: item),
          ];
          final open = [
            ...items.where((e) => !e.item.done),
            ...items.where((e) => e.item.done),
          ];
          final done = items.where((e) => e.item.done).length;
          final toggle = onToggleItem;
          // A row a finger can hit when the items can be ticked here (2.8.2),
          // the line's own height when they are only shown.
          final rowHeight = toggle == null
              ? lineOf(bodyStyle)
              : math.max(lineOf(bodyStyle), 30.0);
          final head = math.max(lineOf(titleStyle), 22.0);
          final rows = ((constraints.maxHeight - head) / rowHeight)
              .floor()
              .clamp(1, 40);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: head,
                child: Row(
                  children: [
                    Expanded(
                      child: heading.isNotEmpty
                          ? headingText(1)
                          : Text(
                              strings.checklistProgress?.call(
                                    done,
                                    items.length,
                                  ) ??
                                  '$done/${items.length}',
                              maxLines: 1,
                              style: bodyStyle?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(width: NexSpacing.xs),
                    _ProgressRing(
                      key: const ValueKey('grid-checklist-ring'),
                      done: done,
                      total: items.length,
                      tint: tint,
                      track: outline,
                    ),
                  ],
                ),
              ),
              for (final entry in open.take(rows))
                _ItemRow(
                  key: ValueKey('grid-item-${entry.index}'),
                  text: entry.item.text,
                  done: entry.item.done,
                  height: rowHeight,
                  tint: tint,
                  outline: outline,
                  muted: muted,
                  style: bodyStyle,
                  onTap: toggle == null
                      ? null
                      : () {
                          nexTick();
                          toggle(entry.index);
                        },
                ),
            ],
          );
        }

        if (note.isAudioMedia && uri != null) {
          // The recording plays from the tile (2.8.2): its words above, as
          // many whole lines as fit, and the player at the foot.
          const strip = 44.0;
          final room = constraints.maxHeight - strip - NexSpacing.xs;
          final words = heading.isNotEmpty ? heading : body;
          final style = heading.isNotEmpty ? titleStyle : bodyStyle;
          final lines = words.isEmpty ? 0 : fitting(words, style, room).$1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lines > 0)
                Text(
                  words,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  textDirection: nexDirectionOf(words),
                  style: style,
                ),
              // Nothing written: the recording is the note, so it has the
              // tile, a little larger and in the middle of it.
              Spacer(flex: lines > 0 ? 1 : 2),
              SizedBox(
                height: lines > 0 ? strip : strip + 12,
                child: NexCardVoice(
                  note: note,
                  tint: tint,
                  durationLabel:
                      strings.durationLabel ?? nexDefaultDurationLabel,
                  playLabel: strings.playLabel ?? 'Play',
                  pauseLabel: strings.pauseLabel ?? 'Pause',
                  height: lines > 0 ? strip : strip + 12,
                ),
              ),
              if (lines == 0) const Spacer(flex: 3),
            ],
          );
        }

        if (note.type == NoteType.link) {
          return _SiteCard(
            note: note,
            title: heading.isNotEmpty ? heading : body,
            tint: tint,
            muted: muted,
            titleStyle: titleStyle,
            bodyStyle: bodyStyle,
            fitting: fitting,
            height: constraints.maxHeight,
          );
        }

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
        final used = headHeight;
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

/// How much of a checklist is done, as a ring with the count inside.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    super.key,
    required this.done,
    required this.total,
    required this.tint,
    required this.track,
  });

  final int done;
  final int total;
  final Color tint;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final value = total == 0 ? 0.0 : done / total;
    final complete = total > 0 && done == total;
    return SizedBox.square(
      dimension: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: NexMotion.of(context, NexMotion.slow),
            curve: NexMotion.curve,
            builder: (context, v, _) => CircularProgressIndicator(
              value: v,
              strokeWidth: 2.5,
              strokeCap: StrokeCap.round,
              color: tint,
              backgroundColor: track.withValues(alpha: 0.35),
            ),
          ),
          if (complete) Icon(Icons.check_rounded, size: 13, color: tint),
        ],
      ),
    );
  }
}

/// One item of a checklist on its tile: the whole row ticks it (2.8.2), a
/// row tall enough for a finger rather than a box too small to hit inside a
/// tile that opens on any other touch.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.text,
    required this.done,
    required this.height,
    required this.tint,
    required this.outline,
    required this.muted,
    required this.style,
    required this.onTap,
  });

  final String text;
  final bool done;
  final double height;
  final Color tint;
  final Color outline;
  final Color muted;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = SizedBox(
      height: height,
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: NexMotion.of(context, NexMotion.pop),
            switchInCurve: NexMotion.popCurve,
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              done
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              key: ValueKey(done),
              size: 16,
              color: done ? tint : outline,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: nexDirectionOf(text),
              style: style?.copyWith(
                color: done ? muted : scheme.onSurface,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
    final tap = onTap;
    if (tap == null) return row;
    return Semantics(
      checked: done,
      button: true,
      label: text,
      excludeSemantics: true,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(NexRadius.sm),
        child: row,
      ),
    );
  }
}

/// A link's tile: the site as a mark in a colour of its own, its name, and
/// what the page is called (2.8.2).
///
/// No picture is fetched from the site for it. A preview image is a request
/// to the page's server every time a link is saved, from a library that is
/// otherwise offline and private; the mark is drawn from the address alone,
/// and the same site always gets the same colour.
class _SiteCard extends StatelessWidget {
  const _SiteCard({
    required this.note,
    required this.title,
    required this.tint,
    required this.muted,
    required this.titleStyle,
    required this.bodyStyle,
    required this.fitting,
    required this.height,
  });

  final Note note;
  final String title;
  final Color tint;
  final Color muted;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;
  final (int, double) Function(String, TextStyle?, double) fitting;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = (Uri.tryParse(note.linkUrl ?? '')?.host ?? '').replaceFirst(
      RegExp(r'^www\.'),
      '',
    );
    final name = host.isEmpty ? '' : host.split('.').first;
    final letter = name.isEmpty ? '#' : name.characters.first.toUpperCase();
    // The same site, the same colour: a hue from its address.
    final hue =
        host.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0xffff) % 360;
    final dark = scheme.brightness == Brightness.dark;
    final mark = HSLColor.fromAHSL(
      1,
      hue.toDouble(),
      0.55,
      dark ? 0.62 : 0.46,
    ).toColor();
    const markSize = 34.0;
    // A title that is only the address again says nothing the mark does not.
    final bare = title.trim().toLowerCase().replaceFirst(
      RegExp(r'^(https?://)?(www\.)?'),
      '',
    );
    final words =
        title.trim() == (note.linkUrl ?? '').trim() ||
            bare == host.toLowerCase() ||
            bare.startsWith('${host.toLowerCase()}/') && !title.contains(' ')
        ? ''
        : title;
    final lines = words.isEmpty
        ? 0
        : fitting(words, titleStyle, height - markSize - NexSpacing.sm).$1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: markSize,
              height: markSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NexRadius.md),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [mark, Color.lerp(mark, tint, 0.45)!],
                ),
              ),
              child: Text(
                letter,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: nexReadableOn(Colors.white, mark),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Text(
                host.isEmpty ? (note.linkUrl ?? '') : host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                textAlign: Directionality.of(context) == TextDirection.rtl
                    ? TextAlign.right
                    : TextAlign.left,
                style: bodyStyle?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        if (lines > 0) ...[
          const SizedBox(height: NexSpacing.sm),
          Text(
            words,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            textDirection: nexDirectionOf(words),
            style: titleStyle,
          ),
        ],
      ],
    );
  }
}
