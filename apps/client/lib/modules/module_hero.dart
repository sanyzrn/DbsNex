import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// The colour a module is known by. Each module has its own hue so a person
/// learns "the green one is Habits, the amber one is Gold" without reading;
/// the same hue is used for the module's hero, its badge and its marks.
/// Saturation and lightness follow the theme's brightness, so it reads on
/// light and dark alike. An id nobody has given a hue falls back to the
/// theme's own primary.
Color nexModuleAccent(BuildContext context, String moduleId) {
  final hue = _moduleHues[moduleId];
  if (hue == null) return Theme.of(context).colorScheme.primary;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return HSLColor.fromAHSL(
    1,
    hue,
    dark ? 0.68 : 0.58,
    dark ? 0.68 : 0.40,
  ).toColor();
}

const _moduleHues = <String, double>{
  'habits': 138,
  'smoke_free': 176,
  'expenses': 158,
  'gold': 42,
  'words': 266,
  'parking': 214,
  'medicine': 350,
  'warranty': 188,
  'maintenance': 24,
  'price_lens': 84,
  'lent_borrowed': 236,
  'occasions': 304,
};

/// The top of a module's home page: one large, calm statement of where things
/// stand — "12 days free", "3 due today" — on a soft wash of the module's own
/// colour, with its icon drawn big and faint behind it. It is the one thing a
/// person should remember about each module, and it is never decoration
/// alone: the [headline] is always a real number or state from their data.
class NexModuleHero extends StatelessWidget {
  const NexModuleHero({
    super.key,
    required this.moduleId,
    required this.icon,
    required this.headline,
    this.eyebrow,
    this.caption,
    this.chips = const [],
    this.child,
    this.semanticsLabel,
    this.captionKey,
  });

  /// Which module this is — picks the colour.
  final String moduleId;
  final IconData icon;

  /// The big line. Keep it short; it scales down rather than wrapping.
  final String headline;

  /// A small line above the headline: what the number is about.
  final String? eyebrow;

  /// A line under the headline, in plain words.
  final String? caption;

  /// Small facts as pills under the caption.
  final List<String> chips;

  /// What can be done from here — a button or two — under everything else.
  final Widget? child;

  /// What a screen reader says for the headline, when the headline alone
  /// ("1,250 IRR") would not say what it is.
  final String? semanticsLabel;

  /// A key on the caption line, for the one test or screen reader hook that
  /// needs to find it.
  final Key? captionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = nexModuleAccent(context, moduleId);
    final dark = theme.brightness == Brightness.dark;
    final shape = BorderRadius.circular(NexRadius.xl);
    Widget cardAt(double t) => Semantics(
      container: true,
      label: semanticsLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              accent.withValues(alpha: dark ? 0.30 : 0.22),
              accent.withValues(alpha: dark ? 0.08 : 0.06),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: Stack(
            children: [
              PositionedDirectional(
                end: -22,
                top: -18,
                child: ExcludeSemantics(
                  child: Transform.rotate(
                    angle: -0.22 - (1 - t) * 0.5,
                    child: Icon(
                      icon,
                      size: 132,
                      color: accent.withValues(alpha: dark ? 0.16 : 0.13),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(NexSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.24),
                          ),
                          child: Icon(icon, size: 18, color: accent),
                        ),
                        if (eyebrow case final eyebrow?) ...[
                          const SizedBox(width: NexSpacing.sm),
                          Flexible(
                            child: Text(
                              eyebrow,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: NexSpacing.md),
                    // Large text scales the line down rather than wrapping
                    // it or pushing the page: the number is the point.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        headline,
                        maxLines: 1,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (caption case final caption?) ...[
                      const SizedBox(height: NexSpacing.xs),
                      Text(
                        caption,
                        key: captionKey,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: NexSpacing.md),
                      Wrap(
                        spacing: NexSpacing.sm,
                        runSpacing: NexSpacing.xs,
                        children: [
                          for (final chip in chips)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  NexRadius.xl,
                                ),
                                color: accent.withValues(alpha: 0.18),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: NexSpacing.sm + 2,
                                  vertical: NexSpacing.xs,
                                ),
                                child: Text(
                                  chip,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (child case final child?) ...[
                      const SizedBox(height: NexSpacing.md),
                      child,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Arrives with a short rise and fade, the big icon behind it turning into
    // place — and not at all when the person has asked the system to remove
    // animations.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: NexMotion.of(context, NexMotion.enter),
      curve: NexMotion.curve,
      builder: (context, t, _) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: cardAt(t),
        ),
      ),
    );
  }
}
