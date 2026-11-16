import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// The pieces the redesigned pages share: tiles in a tool's own colour, two
/// to a row under a heading; rounded panels; and lists drawn as one card.
///
/// Settings set the language first — cards on `surfaceContainerHighest`,
/// `NexRadius.lg` corners, an icon tile leading each row — and Tools, the
/// Library and the lists under them now speak it too.

/// A shelf's name, with its icon and, for the private one, the line that
/// says what keeps it apart.
class NexShelfHeading extends StatelessWidget {
  const NexShelfHeading({
    super.key,
    required this.icon,
    required this.title,
    this.note,
  });

  final IconData icon;
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = this.note;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: NexSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: NexSpacing.xs + 2),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Each tool's own colour, so the shelf reads at a glance — the key is
/// amber, the cards teal — rather than as a row of identical boxes.
enum NexHue {
  // Amber is a step darker than it looks: on its own 16% wash it measured
  // 2.82:1 as an icon (V-06) — the one hue under the 3:1 graphic floor.
  amber(Color(0xFFAE731E), Color(0xFFF2C46D)),
  teal(Color(0xFF1F8A7A), Color(0xFF6FD3C2)),
  violet(Color(0xFF6B4FC8), Color(0xFFB7A4F4)),
  rose(Color(0xFFC2456A), Color(0xFFF29AB3)),
  sky(Color(0xFF2370C2), Color(0xFF8CC0F2)),
  slate(Color(0xFF55606E), Color(0xFFB4BDC8));

  const NexHue(this.light, this.dark);

  final Color light;
  final Color dark;

  Color of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// For the theme [context] is drawn in.
  Color on(BuildContext context) => of(Theme.of(context).brightness);
}

/// Tiles two to a row, each row as tall as its taller tile, so a large text
/// size grows the rows instead of clipping them the way a fixed-ratio grid
/// would.
Widget nexShelfPairs(List<Widget> tiles) => Column(
  children: [
    for (var i = 0; i < tiles.length; i += 2)
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              // An odd one out takes the whole row rather than leaving a
              // hole beside it.
              if (i + 1 < tiles.length) ...[
                const SizedBox(width: 12),
                Expanded(child: tiles[i + 1]),
              ],
            ],
          ),
        ),
      ),
  ],
);

class NexShelfTile extends StatelessWidget {
  const NexShelfTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.hue,
    required this.onTap,
    this.onLongPress,
    this.longPressLabel,
    this.badge,
    this.pinned = false,
    this.compact = false,
    this.compactContent,
    this.progress,
  });

  /// How far along today is, 0 to 1, drawn as a ring round the mark of a
  /// compact tile — habits done out of those due. Null draws no ring. The
  /// words beside it already say the number; the ring is the same fact at a
  /// glance, and says nothing to a screen reader the words have not.
  final double? progress;
  final String title, subtitle;
  final IconData icon;
  final NexHue hue;
  final VoidCallback onTap;

  /// A hold: pinning a tool to the home screen, or taking it off.
  final VoidCallback? onLongPress;

  /// What the hold does, for a screen reader.
  final String? longPressLabel;

  /// A small mark in the corner — a lock on a private tool.
  final IconData? badge;

  /// Pinned to the home screen: a pin beside [badge].
  final bool pinned;

  /// One line, icon and title: the tool as a card among the notes.
  final bool compact;

  /// A pinned module's small local facts, in the title's existing space.
  final Widget? compactContent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = hue.of(theme.brightness);
    final marks = [
      if (pinned) Icon(Icons.push_pin_rounded, size: 14, color: color),
      if (badge case final badge?)
        Icon(badge, size: 16, color: scheme.onSurfaceVariant),
    ];
    final glyph = Container(
      padding: EdgeInsets.all(compact ? 7 : 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
      ),
      child: Icon(
        icon,
        size: compact ? 18 : 22,
        color: theme.brightness == Brightness.dark
            ? Colors.black87
            : Colors.white,
      ),
    );
    // A compact tile keeps the ring's room whether or not it has one, so
    // the marks along a row of tiles line up.
    final mark = !compact
        ? glyph
        : ExcludeSemantics(
            child: NexProgressRing(
              progress: progress,
              color: color,
              radius: 12 + NexProgressRing.gap,
              child: glyph,
            ),
          );
    return Semantics(
      onLongPressHint: longPressLabel,
      label: compactContent == null ? null : title,
      child: NexSurface(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(compact ? NexRadius.lg : 22),
        border: BorderSide(color: color.withValues(alpha: 0.35)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Ink(
            // A wash of the tool's colour from its corner, fading out
            // before it reaches the words.
            decoration: BoxDecoration(
              gradient: context.nexVisualStyle.minimal
                  ? null
                  : LinearGradient(
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                      colors: [
                        color.withValues(alpha: 0.16),
                        color.withValues(alpha: 0.02),
                      ],
                    ),
            ),
            padding: compact
                ? const EdgeInsetsDirectional.fromSTEB(
                    NexSpacing.sm,
                    NexSpacing.sm,
                    NexSpacing.md - NexSpacing.xs,
                    NexSpacing.sm,
                  )
                : const EdgeInsets.all(14),
            child: compact
                ? Row(
                    children: [
                      mark,
                      const SizedBox(width: NexSpacing.sm),
                      Expanded(
                        child:
                            compactContent ??
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                      ),
                      for (final m in marks) ...[
                        const SizedBox(width: NexSpacing.xs),
                        m,
                      ],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          mark,
                          const Spacer(),
                          for (final m in marks) ...[
                            const SizedBox(width: NexSpacing.xs),
                            m,
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// A ring round a rounded mark, filled as far as [progress]: a habit count,
/// the day of a cycle. It takes up its room with or without a ring, so marks
/// beside each other stay level, and eases to a new value rather than
/// jumping — the one moment the ring has news is when it moves.
class NexProgressRing extends StatelessWidget {
  const NexProgressRing({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
    this.progress,
  });

  /// The clear space between the mark and its ring, plus the ring itself.
  static const gap = 4.0;
  static const _stroke = 2.5;

  final Widget child;
  final Color color;

  /// The ring's own corner: the mark's corner plus [gap].
  final double radius;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(padding: const EdgeInsets.all(gap), child: child);
    final target = progress;
    if (target == null) return padded;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target.clamp(0.0, 1.0)),
      duration: NexMotion.of(context, NexMotion.morph),
      curve: NexMotion.moveCurve,
      builder: (context, value, child) => CustomPaint(
        foregroundPainter: _RingPainter(
          progress: value,
          color: color,
          radius: radius,
          stroke: _stroke,
        ),
        child: child,
      ),
      child: padded,
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.radius,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final double radius;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final r = math.min(radius, rect.shortestSide / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    // From the top's middle and clockwise, the way a clock fills.
    final corner = Radius.circular(r);
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + r), radius: corner)
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: corner)
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: corner)
      ..lineTo(rect.left, rect.top + r)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: corner)
      ..close();
    canvas.drawPath(path, paint..color = color.withValues(alpha: 0.22));
    if (progress <= 0) return;
    if (progress >= 1) {
      canvas.drawPath(path, paint..color = color);
      return;
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress),
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.radius != radius ||
      old.stroke != stroke;
}

/// A group of a page on a rounded card, with an optional heading.
class NexPanel extends StatelessWidget {
  const NexPanel({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.padding = const EdgeInsets.all(NexSpacing.md),
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = this.title;
    return NexSurface(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon case final icon?) ...[
                    Icon(icon, size: 20, color: scheme.primary),
                    const SizedBox(width: NexSpacing.sm),
                  ],
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: NexSpacing.sm),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// One row of a lazily built list, drawn so the whole list reads as a single
/// rounded card: the first row rounds the top, the last the bottom, and a
/// hairline sits between them.
class NexGroupedRow extends StatelessWidget {
  const NexGroupedRow({
    super.key,
    required this.index,
    required this.count,
    required this.child,
  });

  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const r = Radius.circular(NexRadius.lg);
    final first = index == 0;
    final last = index == count - 1;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.vertical(
        top: first ? r : Radius.zero,
        bottom: last ? r : Radius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!first)
            Divider(
              height: 1,
              indent: 64,
              endIndent: NexSpacing.md,
              color: scheme.outlineVariant,
            ),
          child,
        ],
      ),
    );
  }
}

/// A row's leading mark on its own rounded tile, as in Settings.
class NexIconTile extends StatelessWidget {
  const NexIconTile(this.icon, {super.key, this.color});

  final IconData icon;

  /// A tint for the tile and its glyph; the neutral one otherwise.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = this.color;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.16) ?? scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      child: Icon(icon, size: 20, color: color ?? scheme.onSurfaceVariant),
    );
  }
}
