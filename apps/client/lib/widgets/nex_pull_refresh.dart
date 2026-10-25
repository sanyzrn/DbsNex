import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:nex_ui/nex_ui.dart';

/// Pull to refresh, in Nex's own shape (2.3.0).
///
/// Not a spinner in a circle. As the list is pulled down it moves with the
/// finger and, in the gap it leaves, the eight arms of Nex's mark reach out
/// from a centre — further the further you pull. Past the point where letting
/// go refreshes, they are all the way out and the centre fills; while the work
/// runs they sweep round in a wave, one after another, the way the mark's
/// arms move in the splash. When it is done a ring spreads from the centre
/// and the list settles back, and [onSettled] lets the page play its own
/// "fresh" moment (a sweep of light over what was refreshed).
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

  /// Called once a refresh has finished, as the ring spreads.
  final VoidCallback? onSettled;
  final String? semanticsLabel;

  @override
  State<NexPullRefresh> createState() => _NexPullRefreshState();
}

enum _Mode { idle, dragging, armed, refreshing, done }

class _NexPullRefreshState extends State<NexPullRefresh>
    with TickerProviderStateMixin {
  /// How far the list has to come down before letting go refreshes.
  static const _threshold = 92.0;

  /// The gap held open while the refresh runs.
  static const _hold = 76.0;
  static const _max = 150.0;

  _Mode _mode = _Mode.idle;

  /// The finger's travel, before resistance.
  double _drag = 0;

  /// How far the list is moved down, which is what is drawn.
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: NexMotion.receipt * 2,
  );
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: NexMotion.receipt,
  );

  @override
  void dispose() {
    _offset.dispose();
    _spin.dispose();
    _ripple.dispose();
    super.dispose();
  }

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
    } else if (!armed && _mode == _Mode.armed) {
      setState(() => _mode = _Mode.dragging);
    }
  }

  Future<void> _release() async {
    if (_mode == _Mode.armed) {
      setState(() => _mode = _Mode.refreshing);
      unawaited(_offset.animateTo(_hold, duration: NexMotion.enter));
      unawaited(_spin.repeat());
      try {
        await widget.onRefresh();
      } catch (_) {}
      if (!mounted) return;
      _spin.stop();
      setState(() => _mode = _Mode.done);
      nexBump();
      widget.onSettled?.call();
      await _ripple.forward(from: 0);
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
    if (mounted) setState(() => _mode = _Mode.idle);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: AnimatedBuilder(
        animation: Listenable.merge([_offset, _spin, _ripple]),
        child: widget.child,
        builder: (context, child) {
          final offset = math.max(0.0, _offset.value);
          return Stack(
            children: [
              Transform.translate(offset: Offset(0, offset), child: child),
              if (offset > 0.5)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: offset,
                  child: IgnorePointer(
                    key: _mode == _Mode.refreshing || _mode == _Mode.done
                        ? const ValueKey('nex-pull-refreshing')
                        : null,
                    child: Semantics(
                      label: _mode == _Mode.refreshing
                          ? widget.semanticsLabel
                          : null,
                      liveRegion: _mode == _Mode.refreshing,
                      child: CustomPaint(
                        painter: _ArmsPainter(
                          reach: (offset / _threshold).clamp(0.0, 1.0),
                          armed:
                              _mode == _Mode.armed ||
                              _mode == _Mode.refreshing ||
                              _mode == _Mode.done,
                          spin: reduced ? 0 : _spin.value,
                          spinning: _mode == _Mode.refreshing,
                          ripple: _ripple.value,
                          color: scheme.primary,
                          soft: scheme.primary.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Eight arms from a centre: their reach follows the pull, and while the
/// refresh runs a wave travels round them.
class _ArmsPainter extends CustomPainter {
  _ArmsPainter({
    required this.reach,
    required this.armed,
    required this.spin,
    required this.spinning,
    required this.ripple,
    required this.color,
    required this.soft,
  });

  final double reach;
  final bool armed;
  final double spin;
  final bool spinning;
  final double ripple;
  final Color color;
  final Color soft;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 2);
    final radius = math.min(26.0, size.height * 0.36);
    if (radius < 4) return;
    const arms = 8;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..color = color;
    for (var i = 0; i < arms; i++) {
      // Each arm reaches out a little after the one before it.
      final own = ((reach * 1.4) - i * 0.05).clamp(0.0, 1.0);
      var length = radius * own;
      if (spinning) {
        // A wave running round the arms.
        final phase = (spin * 2 * math.pi) - i * (2 * math.pi / arms);
        length = radius * (0.55 + 0.45 * (0.5 + 0.5 * math.sin(phase)));
      }
      if (length <= 0.5) continue;
      final angle = -math.pi / 2 + i * (2 * math.pi / arms) + spin * math.pi;
      // Curled, the way the mark's arms are: the end bends sideways.
      final tip = center + Offset(math.cos(angle), math.sin(angle)) * length;
      final bend =
          center +
          Offset(math.cos(angle + 0.5), math.sin(angle + 0.5)) * length * 0.6;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, tip.dx, tip.dy);
      canvas.drawPath(
        path,
        stroke..color = color.withValues(alpha: armed ? 1 : 0.55),
      );
      canvas.drawCircle(tip, armed ? 2.6 : 1.8, Paint()..color = stroke.color);
    }
    // The head: empty while pulling, full once letting go will refresh.
    canvas.drawCircle(
      center,
      armed ? 6.5 : 5 * reach,
      Paint()
        ..color = armed ? color : soft
        ..style = armed ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (ripple > 0 && ripple < 1) {
      canvas.drawCircle(
        center,
        radius * (0.4 + ripple * 2.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - ripple)
          ..color = color.withValues(alpha: 0.6 * (1 - ripple)),
      );
    }
  }

  @override
  bool shouldRepaint(_ArmsPainter old) =>
      old.reach != reach ||
      old.armed != armed ||
      old.spin != spin ||
      old.ripple != ripple ||
      old.color != color;
}

/// A one-shot band of light across [child], played whenever [pulse] changes:
/// what a refresh leaves on the thing it refreshed.
class NexRefreshSheen extends StatefulWidget {
  const NexRefreshSheen({
    super.key,
    required this.pulse,
    required this.child,
    this.strength = 0.16,
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
    final glint = Theme.of(context).colorScheme.primary;
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
                        glint.withValues(alpha: widget.strength * (1 - t)),
                        glint.withValues(alpha: 0),
                      ],
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
