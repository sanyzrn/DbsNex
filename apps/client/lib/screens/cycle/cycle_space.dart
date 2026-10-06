import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import 'cycle_format.dart';

/// «Cycle» is its own room in the app: a blush-to-lavender light, soft
/// glows that drift as the page moves, rounded translucent cards and a rose
/// that every control takes its colour from. Stepping into it should feel
/// like closing a door behind you, not like opening another list.
///
/// Wraps the page — and each sheet the page opens — in [cycleTheme], and
/// paints [CycleBackdrop] behind it. The glows follow the scroll rather
/// than a clock: a page that is never still is tiring to look at, and one
/// that only moves when you do feels alive without asking for attention.
class CycleSpace extends StatefulWidget {
  const CycleSpace({super.key, required this.child});

  final Widget child;

  @override
  State<CycleSpace> createState() => _CycleSpaceState();
}

class _CycleSpaceState extends State<CycleSpace> {
  final _scroll = ValueNotifier<double>(0);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CycleTheme(
    child: Stack(
      fit: StackFit.expand,
      children: [
        CycleBackdrop(scroll: _scroll),
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
              _scroll.value = n.metrics.pixels;
            }
            return false;
          },
          child: widget.child,
        ),
      ],
    ),
  );
}

/// The rose-seeded theme of «Cycle», over whatever theme the app is in: the
/// fonts, sizes and dark or light stay the person's own.
class CycleTheme extends StatelessWidget {
  const CycleTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(data: cycleTheme(base), child: child);
  }
}

ThemeData cycleTheme(ThemeData base) {
  final brightness = base.brightness;
  final dark = brightness == Brightness.dark;
  final rose = cyclePeriodColor(brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFD9506F),
    brightness: brightness,
  ).copyWith(primary: rose, secondary: cycleMauve(brightness));
  final glass = cycleGlass(brightness);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      color: glass,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.xl),
        side: BorderSide(color: cycleHairline(brightness)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide(color: rose.withValues(alpha: dark ? 0.35 : 0.25)),
      backgroundColor: glass,
      selectedColor: rose.withValues(alpha: dark ? 0.32 : 0.18),
      checkmarkColor: rose,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: rose,
        side: BorderSide(color: rose.withValues(alpha: dark ? 0.45 : 0.35)),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: rose),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? rose : null,
      ),
    ),
    dividerTheme: DividerThemeData(color: cycleHairline(brightness), space: 1),
  );
}

/// The second colour of the space: a dusk mauve between the rose and the
/// lavender of the light behind it.
Color cycleMauve(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0xFFB99AE0)
    : const Color(0xFFA26BB4);

/// What a card is made of: frosted, lets the light through.
Color cycleGlass(Brightness brightness) => brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.06)
    : Colors.white.withValues(alpha: 0.62);

Color cycleHairline(Brightness brightness) => brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.09)
    : Colors.white.withValues(alpha: 0.85);

/// Rose into mauve: the big button, today's period days, the ring.
LinearGradient cycleBloom(Brightness brightness) => LinearGradient(
  begin: AlignmentDirectional.centerStart,
  end: AlignmentDirectional.centerEnd,
  colors: [cyclePeriodColor(brightness), cycleMauve(brightness)],
);

/// The light behind the page, and three glows in it.
class CycleBackdrop extends StatelessWidget {
  const CycleBackdrop({super.key, required this.scroll});

  final ValueNotifier<double> scroll;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final still = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [
                    Color(0xFF26161F),
                    Color(0xFF1C1628),
                    Color(0xFF141118),
                  ]
                : const [
                    Color(0xFFFCEAF0),
                    Color(0xFFF4EDFA),
                    Color(0xFFFFF5EE),
                  ],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: TweenAnimationBuilder<double>(
          // The glows open out once, as the door closes behind you.
          tween: Tween(begin: still ? 1 : 0, end: 1),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeOutCubic,
          builder: (context, bloom, _) => ValueListenableBuilder<double>(
            valueListenable: scroll,
            builder: (context, y, _) => CustomPaint(
              painter: _GlowPainter(
                dark: dark,
                bloom: bloom,
                drift: still ? 0 : y,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.dark, required this.bloom, required this.drift});

  final bool dark;
  final double bloom;
  final double drift;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    void glow(Offset at, double radius, Color color) {
      final r = radius * (0.7 + 0.3 * bloom);
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: color.a * bloom),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: r)),
      );
    }

    // Each glow at its own depth, so the page seems to have some.
    glow(
      Offset(w * 0.85, h * 0.12 - drift * 0.18),
      w * 0.75,
      dark ? const Color(0x668E3A5A) : const Color(0x8CF8B4C6),
    );
    glow(
      Offset(w * 0.08, h * 0.45 - drift * 0.10),
      w * 0.7,
      dark ? const Color(0x594B3A78) : const Color(0x80D9C8F6),
    );
    glow(
      Offset(w * 0.9, h * 0.85 - drift * 0.05),
      w * 0.65,
      dark ? const Color(0x406B3F3A) : const Color(0x80FFD8C4),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.dark != dark || old.bloom != bloom || old.drift != drift;
}

/// A frosted card of «Cycle»: large soft corners, a hairline of light at
/// its edge and a rose shadow so faint it reads as warmth, not depth.
class CycleCard extends StatelessWidget {
  const CycleCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(NexSpacing.md),
    this.margin = const EdgeInsets.only(bottom: NexSpacing.md),
    this.tint,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  /// A wash of colour over the glass, for the cards that say something.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final radius = BorderRadius.circular(NexRadius.xl);
    final glass = cycleGlass(brightness);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tint == null
              ? glass
              : Color.alphaBlend(
                  tint!.withValues(alpha: dark ? 0.16 : 0.12),
                  glass,
                ),
          borderRadius: radius,
          border: Border.all(color: cycleHairline(brightness)),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: cyclePeriodColor(brightness).withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// A heading inside the space: quiet, with a small bloom of colour before
/// it instead of a rule under it.
class CycleSectionTitle extends StatelessWidget {
  const CycleSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: NexSpacing.sm,
        bottom: NexSpacing.sm,
        left: NexSpacing.xs,
        right: NexSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: cycleBloom(theme.brightness),
            ),
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                letterSpacing: 0.3,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one big action of the space, as a pill of rose light.
class CycleBloomButton extends StatelessWidget {
  const CycleBloomButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final style = FilledButton.styleFrom(
      backgroundColor: Colors.transparent,
      disabledBackgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(56),
      shape: const StadiumBorder(),
      textStyle: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        gradient: cycleBloom(brightness),
        shadows: [
          BoxShadow(
            color: cyclePeriodColor(brightness).withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: icon == null
          ? FilledButton(onPressed: onPressed, style: style, child: label)
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: icon,
              label: label,
            ),
    );
  }
}

/// Fades and lifts its child in once, the first time it is built.
class CycleRise extends StatelessWidget {
  const CycleRise({super.key, required this.child, this.delay = 0});

  final Widget child;

  /// 0 to 1: how far into the rise this one starts, so a page can arrive a
  /// piece at a time.
  final double delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Interval(delay.clamp(0, 0.6), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// A sheet of «Cycle»: the space's theme, and a blush of its light at the
/// top, so a sheet opened from the page still feels inside it.
class CycleSheet extends StatelessWidget {
  const CycleSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CycleTheme(
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Clear at the very edge, so the glow rises out of the sheet
          // instead of sitting on it as a band.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [
                    Color(0x008E3A5A),
                    Color(0x338E3A5A),
                    Color(0x1A4B3A78),
                    Color(0x004B3A78),
                  ]
                : const [
                    Color(0x00F8B4C6),
                    Color(0x40F8B4C6),
                    Color(0x26D9C8F6),
                    Color(0x00D9C8F6),
                  ],
            stops: const [0, 0.08, 0.3, 0.6],
          ),
        ),
        child: child,
      ),
    );
  }
}
