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
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
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
  amber(Color(0xFFB7791F), Color(0xFFF2C46D)),
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
  });
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
    final mark = Container(
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
    return Semantics(
      onLongPressHint: longPressLabel,
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
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  color.withValues(alpha: 0.16),
                  color.withValues(alpha: 0.02),
                ],
              ),
            ),
            padding: EdgeInsets.all(compact ? 10 : 14),
            child: compact
                ? Row(
                    children: [
                      mark,
                      const SizedBox(width: NexSpacing.sm + 2),
                      Expanded(
                        child: Text(
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
