import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// What a module's card is doing right now.
enum ModuleInstallPhase { idle, installing, removing }

/// How long a module takes to be put together, and taken apart.
///
/// Nothing is downloaded — a module ships inside the app — so this is not a
/// wait for work; it is the moment the module becomes part of the app, given
/// enough time to be seen. Long enough to read as an installation, short
/// enough that nobody waits for it: removing is quicker, as leaving always
/// is (see [NexMotion]).
const moduleInstallTime = Duration(milliseconds: 1500);
const moduleRemoveTime = Duration(milliseconds: 1000);

/// A module's glyph, and what it looks like to be put together or taken
/// apart.
///
/// Installing, small pieces in the module's colour drift in from all around
/// and gather into the tile while a ring closes around it, the glyph firming
/// up as they land; when the ring meets itself the tile settles with a soft
/// pulse and a check pops on its corner. Removing runs it backwards: the ring
/// unwinds and the pieces drift away as the glyph fades.
class ModuleInstallGlyph extends StatelessWidget {
  const ModuleInstallGlyph({
    super.key,
    required this.icon,
    required this.color,
    required this.phase,
    required this.progress,
    this.size = 48,
  });

  final IconData icon;
  final Color color;
  final ModuleInstallPhase phase;
  final Animation<double> progress;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    builder: (context, _) {
      final t = phase == ModuleInstallPhase.idle ? 0.0 : progress.value;
      final installing = phase == ModuleInstallPhase.installing;
      final removing = phase == ModuleInstallPhase.removing;
      final firm = installing
          ? 0.35 + 0.65 * NexMotion.curve.transform(t)
          : removing
          ? 1 - 0.7 * NexMotion.exitCurve.transform(t)
          : 1.0;
      final scale = installing
          ? 0.86 + 0.14 * NexMotion.popCurve.transform(t)
          : removing
          ? 1 - 0.14 * NexMotion.exitCurve.transform(t)
          : 1.0;
      final check = installing
          ? NexMotion.popCurve.transform(((t - 0.84) / 0.16).clamp(0.0, 1.0))
          : 0.0;
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: phase == ModuleInstallPhase.idle
              ? null
              : _AssemblyPainter(t: t, color: color, removing: removing),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18 * firm),
                    borderRadius: BorderRadius.circular(NexRadius.md + 2),
                  ),
                  child: Opacity(
                    opacity: firm.clamp(0.0, 1.0),
                    child: Icon(icon, color: color, size: size * 0.54),
                  ),
                ),
              ),
              if (check > 0)
                PositionedDirectional(
                  end: -4,
                  bottom: -4,
                  child: Transform.scale(
                    scale: check,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_circle, size: 18, color: color),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// The ring and the pieces around a module's tile.
class _AssemblyPainter extends CustomPainter {
  _AssemblyPainter({
    required this.t,
    required this.color,
    required this.removing,
  });

  final double t;
  final Color color;
  final bool removing;

  static const _pieces = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final ring = size.shortestSide / 2 + 9;

    // The track, and the ring closing (or opening) along it.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = color.withValues(alpha: 0.14 * (removing ? 1 - t : 1));
    canvas.drawCircle(centre, ring, track);
    final closed = removing
        ? 1 - NexMotion.exitCurve.transform(t)
        : NexMotion.moveCurve.transform((t / 0.86).clamp(0.0, 1.0));
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5
      ..color = color;
    if (closed >= 0.999) {
      canvas.drawCircle(centre, ring, arc);
    } else if (closed > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: ring),
        -math.pi / 2,
        2 * math.pi * closed,
        false,
        arc,
      );
    }

    // The pieces: each starts a little after the one before, and spirals in
    // (or out) as it goes.
    for (var i = 0; i < _pieces; i++) {
      final delay = (i % 4) * 0.08 + (i ~/ 4) * 0.03;
      final u = ((t - delay) / 0.6).clamp(0.0, 1.0);
      if (u <= 0 || u >= 1) continue;
      final travel = removing
          ? NexMotion.curve.transform(u)
          : 1 - Curves.easeInCubic.transform(u);
      final radius = 12 + (ring + 14 - 12) * travel;
      final angle =
          i * 2 * math.pi / _pieces + (removing ? -1 : 1) * u * math.pi * 0.6;
      final at = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
      final alpha = math.sin(u * math.pi);
      canvas.drawCircle(
        at,
        1.6 + (i % 3) * 0.6,
        Paint()..color = color.withValues(alpha: 0.85 * alpha),
      );
    }

    // The settle: one soft pulse as the ring meets itself.
    if (!removing && t > 0.82) {
      final p = ((t - 0.82) / 0.18).clamp(0.0, 1.0);
      canvas.drawCircle(
        centre,
        ring + 14 * NexMotion.curve.transform(p),
        Paint()..color = color.withValues(alpha: 0.18 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_AssemblyPainter old) =>
      old.t != t || old.color != color || old.removing != removing;
}

/// Where an action button stood while a module is put in or taken out: the
/// step it is on, how far along it is, and a bar filling in its colour.
class ModuleInstallProgress extends StatelessWidget {
  const ModuleInstallProgress({
    super.key,
    required this.color,
    required this.phase,
    required this.progress,
  });

  final Color color;
  final ModuleInstallPhase phase;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName.startsWith('fa');
    final removing = phase == ModuleInstallPhase.removing;
    final steps = removing
        ? [l10n.moduleStepRemoveFromTools, l10n.moduleStepTidy]
        : [
            l10n.moduleStepPrepare,
            l10n.moduleStepSetUp,
            l10n.moduleStepAddToTools,
          ];
    final ink = nexReadableOn(color, scheme.surfaceContainerLow);
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final t = progress.value;
        final filled = removing
            ? 1 - NexMotion.exitCurve.transform(t)
            : NexMotion.moveCurve.transform(t);
        // The step follows the bar, so the words and the fill agree.
        final along = removing ? 1 - filled : filled;
        final step =
            steps[(along * steps.length).floor().clamp(0, steps.length - 1)];
        final whole = (filled * 100).round();
        final percent = persian
            ? '${nexDigits('$whole', persian: true)}٪'
            : '$whole%';
        return Semantics(
          liveRegion: true,
          label: step,
          value: percent,
          child: ExcludeSemantics(
            child: SizedBox(
              height: nexMinTapTarget,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: NexMotion.standard,
                          switchInCurve: NexMotion.curve,
                          switchOutCurve: NexMotion.exitCurve,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: AlignmentDirectional.centerStart,
                            children: [...previous, ?current],
                          ),
                          child: Text(
                            step,
                            key: ValueKey(step),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        percent,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(NexRadius.pill),
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                              color: color.withValues(alpha: 0.16),
                            ),
                          ),
                          FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: filled.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [color.withValues(alpha: 0.7), color],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A card arriving in its new place once its module was added or removed:
/// it rises into position and, for a moment, glows in the module's colour.
class ModuleArrival extends StatelessWidget {
  const ModuleArrival({
    super.key,
    required this.color,
    required this.radius,
    required this.child,
  });

  final Color color;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: NexMotion.of(context, NexMotion.morph + NexMotion.enter),
    builder: (context, t, child) {
      final rise = NexMotion.curve.transform((t / 0.6).clamp(0.0, 1.0));
      final glow = math.sin(t * math.pi);
      return Opacity(
        opacity: rise,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - rise)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                if (glow > 0)
                  BoxShadow(
                    color: color.withValues(alpha: 0.35 * glow),
                    blurRadius: 24 * glow,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: child,
          ),
        ),
      );
    },
    child: child,
  );
}
