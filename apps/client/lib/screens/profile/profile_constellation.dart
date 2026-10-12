import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// The constellation behind the profile's name: Nex's "one mind, a thousand
/// connections", drawn from the name itself.
///
/// Every letter is a star, so a longer name is a larger sky, and the same
/// name always draws the same one. Each star is joined to its nearest
/// neighbours. The sky is alive but quiet: the stars drift a few pixels and
/// twinkle out of step, and every few seconds a spark of light runs along a
/// path of connections — a thought passing through — and lights each star it
/// reaches. Typing the name re-forms it: the old sky fades as the new one
/// gathers.
///
/// It stays out of the middle, where the photo and the name are, and holds
/// still when animations are off.
class ProfileConstellation extends StatefulWidget {
  const ProfileConstellation({
    super.key,
    required this.name,
    required this.color,
  });

  final String name;
  final Color color;

  /// One turn of the sky: drift, twinkle and sparks all repeat on it.
  static const cycle = Duration(seconds: 12);

  /// Whether the sky moves at all.
  ///
  /// Off under `flutter test`, where the clock is fake and a repeating
  /// animation would keep a test that waits for the screen to settle waiting
  /// for ever — as [NexLivingLogotype] does. Not `const`, so a test can turn
  /// it back on.
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  /// A seed that is the same for the same name on every run — unlike
  /// [String.hashCode], which is free to change between them.
  static int seedOf(String name) {
    var seed = 17;
    for (final unit in name.codeUnits) {
      seed = (seed * 31 + unit) & 0x7fffffff;
    }
    return seed;
  }

  /// How many stars a name draws: one a letter, within a sky that is never
  /// empty and never crowded.
  static int starsFor(String name) =>
      (name.replaceAll(RegExp(r'\s'), '').runes.length + 8).clamp(10, 24);

  @override
  State<ProfileConstellation> createState() => _ProfileConstellationState();
}

class _ProfileConstellationState extends State<ProfileConstellation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sky = AnimationController(
    vsync: this,
    duration: ProfileConstellation.cycle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ProfileConstellation.enabled &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!_sky.isAnimating) _sky.repeat();
    } else {
      _sky
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _sky.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name.trim();
    return AnimatedSwitcher(
      duration: NexMotion.of(context, NexMotion.morph),
      switchInCurve: NexMotion.curve,
      switchOutCurve: NexMotion.exitCurve,
      // Filled, not centred: a painter with no child of its own has no size,
      // and every star would be drawn at one point in the middle.
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 1.06, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: CustomPaint(
        key: ValueKey(name),
        size: Size.infinite,
        painter: ConstellationPainter(
          seed: ProfileConstellation.seedOf(name),
          stars: ProfileConstellation.starsFor(name),
          color: widget.color,
          sky: _sky,
        ),
      ),
    );
  }
}

/// Paints one sky at the moment [sky] is at.
class ConstellationPainter extends CustomPainter {
  ConstellationPainter({
    required this.seed,
    required this.stars,
    required this.color,
    required this.sky,
  }) : super(repaint: sky);

  final int seed;
  final int stars;
  final Color color;
  final Animation<double> sky;

  /// Sparks per turn of the sky, and how much of a turn each one takes.
  static const _sparks = 3;
  static const _sparkSpan = 0.22;

  /// The stars where they rest, as fractions of the canvas, with what makes
  /// each one its own: size, how it drifts and when it twinkles.
  List<_Star> _layout() {
    final random = math.Random(seed);
    return [
      for (var i = 0; i < stars; i++)
        () {
          // Pushed away from the middle, where the photo and the name are:
          // a star there would sit behind the words.
          var x = random.nextDouble();
          var y = random.nextDouble();
          final dx = x - 0.5;
          final dy = y - 0.45;
          final reach = math.sqrt(dx * dx + dy * dy);
          if (reach < 0.32) {
            final push = 0.32 / math.max(reach, 0.01);
            x = (0.5 + dx * push).clamp(0.04, 0.96);
            y = (0.45 + dy * push).clamp(0.04, 0.96);
          }
          return _Star(
            at: Offset(x, y),
            radius: 1.2 + random.nextDouble() * 1.8,
            drift: 2 + random.nextDouble() * 4,
            phase: random.nextDouble(),
            turns: 1 + random.nextInt(2),
          );
        }(),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || stars == 0) return;
    final t = sky.value;
    final rest = _layout();
    final points = [
      for (final star in rest)
        Offset(star.at.dx * size.width, star.at.dy * size.height) +
            Offset.fromDirection(
              2 * math.pi * (t * star.turns + star.phase),
              star.drift,
            ),
    ];

    // Each star to its two nearest, once per pair.
    final edges = <(int, int)>{};
    final neighbours = List.generate(stars, (_) => <int>[]);
    for (var a = 0; a < stars; a++) {
      final order = List.generate(stars, (i) => i)
        ..sort(
          (x, y) => (rest[x].at - rest[a].at).distance.compareTo(
            (rest[y].at - rest[a].at).distance,
          ),
        );
      for (final b in order.skip(1).take(2)) {
        edges.add(a < b ? (a, b) : (b, a));
        neighbours[a].add(b);
        neighbours[b].add(a);
      }
    }
    final longest = size.shortestSide * 0.6;
    final line = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in edges) {
      final length = (points[a] - points[b]).distance;
      final near = (1 - length / longest).clamp(0.25, 1.0);
      line.color = color.withValues(alpha: 0.26 * near);
      canvas.drawLine(points[a], points[b], line);
    }

    // The sparks: each walks four stars from a start the seed chooses, so
    // every name has its own three paths.
    final lit = List<double>.filled(stars, 0);
    for (var s = 0; s < _sparks; s++) {
      final start = s / _sparks;
      final u = (t - start) / _sparkSpan;
      if (u <= 0 || u >= 1) continue;
      final path = _walk(neighbours, (seed + s * 7) % stars, 4);
      if (path.length < 2) continue;
      final along = Curves.easeInOutSine.transform(u) * (path.length - 1);
      final leg = along.floor().clamp(0, path.length - 2);
      final within = along - leg;
      final from = points[path[leg]];
      final to = points[path[leg + 1]];
      final at = Offset.lerp(from, to, within)!;
      final fade = math.sin(u * math.pi);
      // The leg it is on brightens behind it.
      canvas.drawLine(
        from,
        at,
        Paint()
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.6 * fade),
      );
      canvas.drawCircle(
        at,
        6,
        Paint()
          ..color = color.withValues(alpha: 0.32 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        at,
        1.8,
        Paint()..color = color.withValues(alpha: 0.9 * fade),
      );
      for (var i = 0; i <= leg; i++) {
        lit[path[i]] = math.max(lit[path[i]], fade);
      }
      lit[path[leg + 1]] = math.max(lit[path[leg + 1]], fade * within);
    }

    final dot = Paint();
    final halo = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (var i = 0; i < stars; i++) {
      final star = rest[i];
      final twinkle =
          0.5 + 0.5 * math.sin(2 * math.pi * (t * 3 * star.turns + star.phase));
      final glow = math.max(lit[i], 0.0);
      final alpha = lerpDouble(0.34, 0.66, twinkle)! + 0.34 * glow;
      if (glow > 0.05) {
        halo.color = color.withValues(alpha: 0.25 * glow);
        canvas.drawCircle(points[i], star.radius + 5, halo);
      }
      dot.color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(points[i], star.radius + glow, dot);
    }
  }

  /// A path of [length] stars from [start], never going back on itself.
  static List<int> _walk(List<List<int>> neighbours, int start, int length) {
    final path = [start];
    while (path.length < length) {
      final next = neighbours[path.last].where((n) => !path.contains(n));
      if (next.isEmpty) break;
      path.add(next.first);
    }
    return path;
  }

  @override
  bool shouldRepaint(ConstellationPainter old) =>
      old.seed != seed ||
      old.stars != stars ||
      old.color != color ||
      old.sky != sky;
}

class _Star {
  const _Star({
    required this.at,
    required this.radius,
    required this.drift,
    required this.phase,
    required this.turns,
  });

  final Offset at;
  final double radius;
  final double drift;
  final double phase;
  final int turns;
}
