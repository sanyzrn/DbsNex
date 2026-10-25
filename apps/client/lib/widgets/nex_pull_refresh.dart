import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show Float32List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:nex_ui/nex_ui.dart';

import 'nex_brand.dart';

/// Pull to refresh, in Nex's own shape (rebuilt in 2.3.3).
///
/// As the list is pulled down it moves with the finger and opens a strip of
/// sky behind it: three dotted clouds at three depths, drifting, and the
/// "nex" wordmark in the middle. The further the pull, the more of the x's
/// blue stroke is written in; past the point where letting go refreshes, the
/// dot after it pops into place with a small bounce. While the work runs the
/// wordmark does what it does at the top of the timeline — a light runs
/// along the stroke and the dot hops — and the clouds drift a little faster.
/// When it is done the dot gives one last hop, the list settles back, and
/// [onSettled] lets the page play its own "fresh" moment.
///
/// Works with clamping (Android) and bouncing (iOS) physics alike: it reads
/// the overscroll notifications a pull at the top produces, not the list's
/// offset alone.
class NexPullRefresh extends StatefulWidget {
  const NexPullRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.onSettled,
    this.semanticsLabel,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final ScrollNotificationPredicate notificationPredicate;

  /// Called once a refresh has finished, as the list settles.
  final VoidCallback? onSettled;
  final String? semanticsLabel;

  @override
  State<NexPullRefresh> createState() => _NexPullRefreshState();
}

enum _Mode { idle, dragging, armed, refreshing, done }

class _NexPullRefreshState extends State<NexPullRefresh>
    with TickerProviderStateMixin {
  /// How far the list has to come down before letting go refreshes.
  static const _threshold = 104.0;

  /// The strip held open while the refresh runs.
  static const _hold = 96.0;
  static const _max = 168.0;

  _Mode _mode = _Mode.idle;

  /// The finger's travel, before resistance.
  double _drag = 0;

  /// How far the list is moved down, which is what is drawn.
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );

  /// One turn of the wordmark's movement while the refresh runs.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: NexMotion.receipt * 2,
  );

  /// The dot arriving once letting go will refresh, and its last hop.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: NexMotion.receipt,
  );

  /// The clouds' drift: one slow lap, running only while the sky shows.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  @override
  void dispose() {
    _offset.dispose();
    _loop.dispose();
    _pop.dispose();
    _drift.dispose();
    super.dispose();
  }

  bool get _still => MediaQuery.disableAnimationsOf(context);

  /// A pull that gets heavier as it goes, like something on a spring.
  double _resist(double drag) => _max * (1 - math.exp(-drag / _max));

  bool _onNotification(ScrollNotification n) {
    if (!widget.notificationPredicate(n)) return false;
    if (_mode == _Mode.refreshing || _mode == _Mode.done) return false;
    if (n is ScrollStartNotification &&
        n.dragDetails != null &&
        n.metrics.extentBefore == 0) {
      _mode = _Mode.dragging;
      _drag = 0;
      _offset.stop();
      if (!_still && !_drift.isAnimating) unawaited(_drift.repeat());
      return false;
    }
    if (_mode == _Mode.idle) return false;
    if (n is OverscrollNotification && n.dragDetails != null) {
      if (n.overscroll < 0) _move(_drag - n.overscroll);
    } else if (n is ScrollUpdateNotification) {
      if (n.metrics.pixels < 0) {
        // Bouncing physics: the list itself went past the top.
        _move(-n.metrics.pixels * 1.6);
      } else if ((n.scrollDelta ?? 0) > 0 && _drag > 0) {
        // Pushed back up before letting go.
        _move(math.max(0, _drag - n.scrollDelta!));
      }
    } else if (n is ScrollEndNotification ||
        (n is UserScrollNotification && n.direction == ScrollDirection.idle)) {
      unawaited(_release());
    }
    return false;
  }

  void _move(double drag) {
    _drag = drag;
    _offset.value = _resist(drag);
    final armed = _offset.value >= _threshold;
    if (armed && _mode == _Mode.dragging) {
      nexTick();
      setState(() => _mode = _Mode.armed);
      unawaited(_pop.forward(from: 0));
    } else if (!armed && _mode == _Mode.armed) {
      setState(() => _mode = _Mode.dragging);
      unawaited(_pop.reverse());
    }
  }

  Future<void> _release() async {
    if (_mode == _Mode.armed) {
      setState(() => _mode = _Mode.refreshing);
      unawaited(_offset.animateTo(_hold, duration: NexMotion.enter));
      if (!_still) unawaited(_loop.repeat());
      try {
        await widget.onRefresh();
      } catch (_) {}
      if (!mounted) return;
      _loop.stop();
      _loop.value = 0;
      setState(() => _mode = _Mode.done);
      nexBump();
      widget.onSettled?.call();
      // The last hop, then the sky closes.
      if (!_still) await _pop.forward(from: 0);
      if (!mounted) return;
    } else if (_mode != _Mode.dragging) {
      return;
    }
    _drag = 0;
    await _offset.animateTo(
      0,
      duration: NexMotion.exit,
      curve: NexMotion.exitCurve,
    );
    if (!mounted) return;
    _drift.stop();
    _pop.value = 0;
    setState(() => _mode = _Mode.idle);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: AnimatedBuilder(
        animation: Listenable.merge([_offset, _loop, _pop, _drift]),
        child: widget.child,
        builder: (context, child) {
          final offset = math.max(0.0, _offset.value);
          final working = _mode == _Mode.refreshing || _mode == _Mode.done;
          return Stack(
            children: [
              if (offset > 0.5)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: offset,
                  child: IgnorePointer(
                    key: working ? const ValueKey('nex-pull-refreshing') : null,
                    child: Semantics(
                      label: _mode == _Mode.refreshing
                          ? widget.semanticsLabel
                          : null,
                      liveRegion: _mode == _Mode.refreshing,
                      child: CustomPaint(
                        painter: _SkyPainter(
                          height: offset,
                          reach: (offset / _threshold).clamp(0.0, 1.0),
                          armed: _mode != _Mode.dragging,
                          pop: _pop.value,
                          loop: _mode == _Mode.refreshing ? _loop.value : 0,
                          finishing: _mode == _Mode.done,
                          drift: _drift.value * (working ? 1.6 : 1),
                          sky: Color.alphaBlend(
                            scheme.onSurface.withValues(alpha: 0.035),
                            scheme.surfaceContainerLowest,
                          ),
                          cloud: scheme.onSurface,
                          ink: NexBrand.ink(theme.brightness),
                          accent: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.translate(offset: Offset(0, offset), child: child),
            ],
          );
        },
      ),
    );
  }
}

/// The strip of sky a pull opens: dotted clouds drifting at three depths,
/// and the wordmark in the middle.
class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required this.height,
    required this.reach,
    required this.armed,
    required this.pop,
    required this.loop,
    required this.finishing,
    required this.drift,
    required this.sky,
    required this.cloud,
    required this.ink,
    required this.accent,
  });

  final double height;
  final double reach;
  final bool armed;
  final double pop;
  final double loop;
  final bool finishing;
  final double drift;
  final Color sky;
  final Color cloud;
  final Color ink;
  final Color accent;

  /// Where each cloud sits: across (0–1), how high in the strip, how big,
  /// how faint, and how fast it drifts — the near ones faster.
  static const _clouds = [
    (x: 0.05, y: 0.16, scale: 0.72, alpha: 0.17, speed: 0.6, seed: 1),
    (x: 0.30, y: 0.04, scale: 0.45, alpha: 0.09, speed: 0.3, seed: 2),
    (x: 0.48, y: 0.22, scale: 0.60, alpha: 0.14, speed: 0.5, seed: 3),
    (x: 0.66, y: 0.08, scale: 0.50, alpha: 0.10, speed: 0.35, seed: 1),
    (x: 0.84, y: 0.18, scale: 0.80, alpha: 0.20, speed: 0.9, seed: 3),
    (x: 0.97, y: 0.02, scale: 0.40, alpha: 0.08, speed: 0.25, seed: 2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = sky);
    // The clouds come in once there is sky above the wordmark for them, so
    // a short pull shows the wordmark alone rather than the two crowded.
    final open = Curves.easeOut.transform(
      ((size.height - 72) / 36).clamp(0.0, 1.0),
    );
    for (final c in _clouds) {
      if (open <= 0) break;
      final dots = _DottedCloud.of(c.seed, c.scale);
      // Drifting sideways, round and round, the near ones faster.
      final span = size.width + dots.width;
      final x = (c.x * span + drift * span * c.speed) % span - dots.width / 2;
      // Settling into place as the strip opens.
      final y = size.height * c.y + (1 - open) * 18;
      canvas.drawRawPoints(
        ui.PointMode.points,
        dots.at(Offset(x, y)),
        Paint()
          ..color = cloud.withValues(alpha: c.alpha * open)
          ..strokeWidth = _DottedCloud.dot
          ..strokeCap = StrokeCap.square,
      );
    }

    // The wordmark, fading and growing in with the pull.
    const wordHeight = 21.0;
    final bounds = NexBrand.wordBounds;
    final wordWidth = wordHeight * bounds.width / bounds.height;
    final show = ((reach - 0.25) / 0.5).clamp(0.0, 1.0);
    if (show <= 0) return;
    final scale = 0.86 + 0.14 * Curves.easeOutBack.transform(show);
    // A fixed distance above the list, so it rises with the pull.
    final center = Offset(size.width / 2, size.height - 30);
    // The dot: arrives with a bounce once letting go will refresh, hops
    // while the work runs, and hops once more when it is done.
    final cycle = loop;
    double hop(double t, double a, double b) =>
        math.sin(math.pi * ((t - a) / (b - a)).clamp(0.0, 1.0));
    final dot = armed
        ? (finishing ? 1.0 : Curves.elasticOut.transform(pop.clamp(0.0, 1.0)))
        : 0.0;
    final lift = finishing ? hop(pop, 0, 0.7) : hop(cycle, 0.35, 0.85);
    final squash = finishing
        ? hop(pop, 0.7, 1) * 0.18
        : hop(cycle, 0.85, 1) * 0.18;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale)
      ..translate(-wordWidth / 2, -wordHeight / 2);
    nexPaintLogotype(
      canvas,
      Size(wordWidth, wordHeight),
      ink: ink,
      accent: accent,
      opacity: show,
      written: armed ? 1 : reach,
      light: Curves.easeInOutCubic.transform(((cycle) / 0.6).clamp(0.0, 1.0)),
      dot: dot,
      lift: lift,
      squash: squash,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.height != height ||
      old.reach != reach ||
      old.armed != armed ||
      old.pop != pop ||
      old.loop != loop ||
      old.finishing != finishing ||
      old.drift != drift ||
      old.sky != sky ||
      old.accent != accent;
}

/// A cloud drawn as a grid of small square dots — solid inside, dithered
/// toward its edge — worked out once per shape and size and kept.
class _DottedCloud {
  _DottedCloud._(this._points, this.width);

  /// The size of a dot, and the step between them.
  static const dot = 2.0;
  static const _step = 3.0;

  final List<Offset> _points;
  final double width;

  static final _cache = <(int, double), _DottedCloud>{};

  static _DottedCloud of(int seed, double scale) =>
      _cache[(seed, scale)] ??= _build(seed, scale);

  /// Puffs of a stepped, low cloud: a flat base and two or three domes.
  static _DottedCloud _build(int seed, double scale) {
    final w = 120.0 * scale;
    final h = 40.0 * scale;
    final puffs = switch (seed) {
      1 => [(0.30, 0.55, 0.30), (0.55, 0.38, 0.34), (0.80, 0.60, 0.24)],
      2 => [(0.25, 0.50, 0.26), (0.50, 0.42, 0.30), (0.75, 0.55, 0.22)],
      _ => [(0.22, 0.60, 0.22), (0.45, 0.35, 0.32), (0.72, 0.48, 0.28)],
    };
    double inside(double x, double y) {
      // How deep into the cloud a point is: above 0 inside, 1 well within.
      var best = -1.0;
      for (final (cx, cy, r) in puffs) {
        final dx = (x / w - cx) / (r * 1.2);
        final dy = (y / h - cy) / r;
        best = math.max(best, 1 - math.sqrt(dx * dx + dy * dy));
      }
      // The flat base.
      if (y / h > 0.62 && y / h < 0.95 && x / w > 0.1 && x / w < 0.92) {
        best = math.max(best, math.min(0.95 - y / h, 0.3) * 2);
      }
      return best;
    }

    final points = <Offset>[];
    var row = 0;
    for (var y = 0.0; y < h; y += _step, row++) {
      var col = 0;
      for (var x = 0.0; x < w; x += _step, col++) {
        final depth = inside(x, y);
        if (depth <= 0) continue;
        // Dithered near the edge: every other dot, then every one.
        if (depth < 0.22 && (row + col).isOdd) continue;
        points.add(Offset(x, y));
      }
    }
    return _DottedCloud._(points, w);
  }

  /// The dots, moved to [origin], ready to draw.
  Float32List at(Offset origin) {
    final out = Float32List(_points.length * 2);
    for (var i = 0; i < _points.length; i++) {
      out[i * 2] = _points[i].dx + origin.dx;
      out[i * 2 + 1] = _points[i].dy + origin.dy;
    }
    return out;
  }
}

/// A one-shot band of light across [child], played whenever [pulse] changes:
/// what a refresh leaves on the thing it refreshed.
class NexRefreshSheen extends StatefulWidget {
  const NexRefreshSheen({
    super.key,
    required this.pulse,
    required this.child,
    this.strength = 0.3,
  });

  final ValueListenable<int> pulse;
  final Widget child;

  /// How bright the band is at its peak.
  final double strength;

  @override
  State<NexRefreshSheen> createState() => _NexRefreshSheenState();
}

class _NexRefreshSheenState extends State<NexRefreshSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: NexMotion.receipt * 1.5,
  );

  @override
  void initState() {
    super.initState();
    widget.pulse.addListener(_play);
  }

  @override
  void didUpdateWidget(NexRefreshSheen old) {
    super.didUpdateWidget(old);
    if (old.pulse != widget.pulse) {
      old.pulse.removeListener(_play);
      widget.pulse.addListener(_play);
    }
  }

  void _play() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    unawaited(_sweep.forward(from: 0));
  }

  @override
  void dispose() {
    widget.pulse.removeListener(_play);
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A lit band of the accent, lightened so it reads as light on a dark
    // page as well as a light one (2.3.4: the plain accent at a few percent
    // was not seen at all).
    final scheme = Theme.of(context).colorScheme;
    final glint = Color.lerp(
      scheme.primary,
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : scheme.primaryContainer,
      0.35,
    )!;
    return AnimatedBuilder(
      animation: _sweep,
      child: widget.child,
      builder: (context, child) {
        final t = _sweep.value;
        if (t <= 0 || t >= 1) return child!;
        final eased = NexMotion.moveCurve.transform(t);
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.6 + eased * 3.2, -1),
                      end: Alignment(-0.6 + eased * 3.2, 1),
                      colors: [
                        glint.withValues(alpha: 0),
                        glint.withValues(
                          alpha: widget.strength * math.sin(math.pi * t),
                        ),
                        glint.withValues(alpha: 0),
                      ],
                      stops: const [0.3, 0.5, 0.7],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
