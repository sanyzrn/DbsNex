part of '../onboarding_screen.dart';

/// A picture that plays once each time its page arrives, then holds still.
///
/// Once rather than on a loop: the words under it are what the page is for,
/// and something still moving beside a paragraph is something competing with
/// it. Leaving the page puts it back to its first frame, so coming back plays
/// it again instead of showing a picture that already happened.
abstract class _Art extends StatefulWidget {
  const _Art({required this.play});

  final bool play;

  Duration get duration;
}

abstract class _ArtState<T extends _Art> extends State<T>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.play) _start();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play && !oldWidget.play) _start();
    if (!widget.play && oldWidget.play) controller.value = 0;
  }

  void _start() {
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = 1;
    } else {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Where [t] is between [begin] and [end], eased, as 0 to 1.
  double span(double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(
        ((controller.value - begin) / (end - begin)).clamp(0.0, 1.0),
      );
}

/// The small panel the app-shaped pictures are drawn on: a phone's worth of
/// surface, rounded like the app's own sheets.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(NexRadius.xl),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A note card in miniature, with its type's colour on the leading square.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.icon, required this.hue, required this.child});

  final IconData icon;
  final NexHue hue;
  final Widget child;

  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = hue.of(theme.brightness);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(NexRadius.md + 2),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(NexRadius.sm + 2),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A line of "text" in a miniature: a rounded bar.
class _Bar extends StatelessWidget {
  const _Bar(this.factor, {this.strong = false});

  final double factor;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: factor,
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: ink.withValues(alpha: strong ? 0.5 : 0.22),
          borderRadius: BorderRadius.circular(NexRadius.xs),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Welcome: one mind, a thousand connections.
// ---------------------------------------------------------------------------

/// The splash's story told at rest: the octopus in the middle, and the six
/// pieces of a day — a thought, a photo, a person, a task, a moment, a voice —
/// drifting in from the edge, each tied to the arm that catches it.
///
/// The same six as [NexSplash] and the same points on the mark, so the first
/// page reads as the picture the app opened on, settling.
class _WelcomeArt extends _Art {
  const _WelcomeArt({required super.play});

  @override
  Duration get duration => const Duration(milliseconds: 2400);

  @override
  State<_WelcomeArt> createState() => _WelcomeArtState();
}

class _Piece {
  const _Piece(this.icon, this.anchor, this.hue);

  final IconData icon;

  /// Where on the mark it is caught, in the mark's own coordinates.
  final Offset anchor;
  final NexHue hue;
}

const _pieces = [
  _Piece(Icons.lightbulb_outline, Offset(118, 24), NexHue.amber),
  _Piece(Icons.photo_outlined, Offset(49, 95), NexHue.rose),
  _Piece(Icons.person_outline, Offset(187, 95), NexHue.sky),
  _Piece(Icons.check_circle_outline, Offset(24, 222), NexHue.teal),
  _Piece(Icons.schedule, Offset(212, 222), NexHue.violet),
  _Piece(Icons.mic_none, Offset(70, 248), NexHue.slate),
];

class _WelcomeArtState extends _ArtState<_WelcomeArt> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final side = math.min(constraints.maxWidth, constraints.maxHeight);
          final centre = Offset(
            constraints.maxWidth / 2,
            constraints.maxHeight / 2,
          );
          final bounds = NexBrand.markBounds;
          final markWidth = side * 0.36;
          final scale = markWidth / bounds.width;
          Offset onScreen(Offset p) => centre + (p - bounds.center) * scale;
          final radius = side * 0.44;
          final mark = span(0, 0.28);

          final chips = <Widget>[];
          final ties = <_Tie>[];
          for (final (i, piece) in _pieces.indexed) {
            final start = 0.18 + i * 0.07;
            final arrive = span(start, start + 0.32);
            final tie = span(start + 0.22, start + 0.45, Curves.easeInOut);
            final ripple = span(start + 0.4, start + 0.62, Curves.easeOut);
            final anchor = onScreen(piece.anchor);
            final outward = piece.anchor - bounds.center;
            final direction = outward / outward.distance;
            final at = centre + direction * radius * (1.25 - 0.25 * arrive);
            ties.add(
              _Tie(
                from: at,
                to: anchor,
                progress: tie,
                ripple: ripple,
                color: piece.hue.of(brightness),
              ),
            );
            chips.add(
              Positioned(
                left: at.dx - 20,
                top: at.dy - 20,
                child: Opacity(
                  opacity: arrive,
                  child: Transform.scale(
                    scale: 0.7 + 0.3 * arrive,
                    child: _PieceChip(piece: piece),
                  ),
                ),
              ),
            );
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _WelcomePainter(
                    centre: centre,
                    radius: radius,
                    ring: span(0.05, 0.5),
                    ties: ties,
                    ringColor: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
              Positioned(
                left: centre.dx - markWidth / 2,
                top: centre.dy - bounds.height * scale / 2,
                child: Opacity(
                  opacity: mark,
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * mark,
                    child: NexMark(size: markWidth, semanticLabel: null),
                  ),
                ),
              ),
              ...chips,
            ],
          );
        },
      ),
    );
  }
}

class _PieceChip extends StatelessWidget {
  const _PieceChip({required this.piece});

  final _Piece piece;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = piece.hue.of(theme.brightness);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(
          color.withValues(alpha: 0.16),
          theme.colorScheme.surfaceContainerLowest,
        ),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(piece.icon, size: 20, color: color),
    );
  }
}

class _Tie {
  const _Tie({
    required this.from,
    required this.to,
    required this.progress,
    required this.ripple,
    required this.color,
  });

  final Offset from;
  final Offset to;
  final double progress;
  final double ripple;
  final Color color;
}

class _WelcomePainter extends CustomPainter {
  _WelcomePainter({
    required this.centre,
    required this.radius,
    required this.ring,
    required this.ties,
    required this.ringColor,
  });

  final Offset centre;
  final double radius;
  final double ring;
  final List<_Tie> ties;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Two quiet orbits the pieces arrive on.
    if (ring > 0) {
      final orbit = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ringColor.withValues(alpha: 0.7 * ring);
      canvas
        ..drawCircle(centre, radius * (0.8 + 0.2 * ring), orbit)
        ..drawCircle(
          centre,
          radius * (0.55 + 0.15 * ring),
          orbit..color = ringColor.withValues(alpha: 0.4 * ring),
        );
    }
    for (final tie in ties) {
      if (tie.progress > 0) {
        canvas.drawLine(
          tie.from,
          Offset.lerp(tie.from, tie.to, tie.progress)!,
          Paint()
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round
            ..color = tie.color.withValues(alpha: 0.55),
        );
      }
      if (tie.ripple > 0 && tie.ripple < 1) {
        canvas.drawCircle(
          tie.to,
          3 + 10 * tie.ripple,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = tie.color.withValues(alpha: 0.8 * (1 - tie.ripple)),
        );
      }
      if (tie.ripple >= 1) {
        canvas.drawCircle(tie.to, 2.5, Paint()..color = tie.color);
      }
    }
  }

  @override
  bool shouldRepaint(_WelcomePainter old) => true;
}

// ---------------------------------------------------------------------------
// 4. Yours: a lock closing round all of it.
// ---------------------------------------------------------------------------

class _YoursArt extends _Art {
  const _YoursArt({required super.play});

  @override
  Duration get duration => const Duration(milliseconds: 2400);

  @override
  State<_YoursArt> createState() => _YoursArtState();
}

class _YoursArtState extends _ArtState<_YoursArt> {
  static const _satellites = [
    (Icons.airplanemode_active, NexHue.sky),
    (Icons.fingerprint, NexHue.teal),
    (Icons.key_outlined, NexHue.amber),
    (Icons.folder_zip_outlined, NexHue.violet),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final side = math.min(constraints.maxWidth, constraints.maxHeight);
          final centre = Offset(
            constraints.maxWidth / 2,
            constraints.maxHeight / 2,
          );
          final radius = side * 0.36;
          final core = span(0, 0.3, Curves.easeOutBack);
          final seal = span(0.15, 0.62, Curves.easeInOutCubic);
          final glow = span(0.6, 0.9);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SealPainter(
                    centre: centre,
                    radius: radius,
                    seal: seal,
                    glow: glow,
                    color: scheme.primary,
                    faint: scheme.outlineVariant,
                  ),
                ),
              ),
              Positioned(
                left: centre.dx - 52,
                top: centre.dy - 52,
                child: Opacity(
                  opacity: core.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * core,
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primaryContainer,
                      ),
                      child: Icon(
                        // Open until the ring has closed round it.
                        seal < 1 ? Icons.lock_open_outlined : Icons.lock,
                        size: 46,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
              for (final (i, (icon, hue)) in _satellites.indexed)
                () {
                  final start = 0.45 + i * 0.1;
                  final shown = span(start, start + 0.25, Curves.easeOutBack);
                  final angle = -math.pi * 3 / 4 + i * math.pi / 2;
                  final at = centre + Offset.fromDirection(angle, radius);
                  final color = hue.of(theme.brightness);
                  return Positioned(
                    left: at.dx - 22,
                    top: at.dy - 22,
                    child: Opacity(
                      opacity: shown.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: shown.clamp(0.0, 1.2),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color.alphaBlend(
                              color.withValues(alpha: 0.18),
                              scheme.surface,
                            ),
                            border: Border.all(
                              color: color.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Icon(icon, size: 21, color: color),
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          );
        },
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  _SealPainter({
    required this.centre,
    required this.radius,
    required this.seal,
    required this.glow,
    required this.color,
    required this.faint,
  });

  final Offset centre;
  final double radius;
  final double seal;
  final double glow;
  final Color color;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = faint,
    );
    if (seal > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * seal,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
    // Once it is closed, one soft ring leaves it.
    if (glow > 0 && glow < 1) {
      canvas.drawCircle(
        centre,
        radius + 18 * glow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.35 * (1 - glow)),
      );
    }
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      old.seal != seal || old.glow != glow || old.color != color;
}
