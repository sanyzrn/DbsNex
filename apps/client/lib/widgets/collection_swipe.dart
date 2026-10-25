import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// A card that can be swiped toward the start edge to act on it — and only
/// that way (2.3.2).
///
/// It replaces a [Dismissible], which claims a horizontal drag in *either*
/// direction the moment it passes the slop: told to act only toward the
/// start, it still took the drag the other way and simply did not move, so
/// the page's own swipe back never started from a card. Here the drag is
/// given up as soon as the finger heads the other way, and the page behind
/// takes it.
class NexStartSwipe extends StatefulWidget {
  const NexStartSwipe({
    super.key,
    required this.onSwipe,
    required this.background,
    required this.child,
  });

  final VoidCallback onSwipe;

  /// What the moving card uncovers, laid out under it at full size.
  final Widget background;
  final Widget child;

  @override
  State<NexStartSwipe> createState() => _NexStartSwipeState();
}

class _NexStartSwipeState extends State<NexStartSwipe>
    with SingleTickerProviderStateMixin {
  /// How far across a slow drag has to go to count.
  static const _commitFraction = 0.35;

  /// A flick counts at any distance, in logical pixels per second.
  static const _commitVelocity = 700.0;

  /// The card's offset toward the start, as a fraction of its width.
  late final AnimationController _offset = AnimationController(
    vsync: this,
    duration: NexMotion.standard,
  );
  bool _gone = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  /// +1 when the start edge is on the left.
  double get _toStart =>
      Directionality.of(context) == TextDirection.rtl ? 1.0 : -1.0;

  double get _width => context.size?.width ?? 1;

  void _onUpdate(DragUpdateDetails details) {
    if (_gone) return;
    final moved = (details.primaryDelta ?? 0) * _toStart / _width;
    _offset.value = (_offset.value + moved).clamp(0.0, 1.0);
  }

  void _onEnd(DragEndDetails details) {
    if (_gone) return;
    final velocity = details.velocity.pixelsPerSecond.dx * _toStart;
    final commit =
        velocity > _commitVelocity ||
        (velocity > -_commitVelocity && _offset.value > _commitFraction);
    if (!commit) {
      unawaited(_offset.animateBack(0, curve: NexMotion.curve));
      return;
    }
    _gone = true;
    unawaited(
      _offset
          .animateTo(1, curve: NexMotion.exitCurve)
          .then((_) => widget.onSwipe()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        _StartwardDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_StartwardDragRecognizer>(
              () => _StartwardDragRecognizer(debugOwner: this),
              (recognizer) => recognizer
                ..toStart = _toStart
                ..onUpdate = _onUpdate
                ..onEnd = _onEnd
                ..onCancel = () {
                  if (!_gone) unawaited(_offset.animateBack(0));
                },
            ),
      },
      child: AnimatedBuilder(
        animation: _offset,
        child: widget.child,
        builder: (context, child) {
          if (_offset.value == 0) return child!;
          return Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: math.min(1, _offset.value * 3),
                  child: widget.background,
                ),
              ),
              FractionalTranslation(
                translation: Offset(_offset.value * _toStart, 0),
                child: child,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A horizontal drag that steps aside for one heading away from the start
/// edge: past a few pixels that way it rejects itself, before it could win,
/// and the page's swipe back is left alone in the arena.
class _StartwardDragRecognizer extends HorizontalDragGestureRecognizer {
  _StartwardDragRecognizer({super.debugOwner});

  double toStart = -1;

  /// Movement before this recognizer has won, signed so toward the start is
  /// positive.
  double _travel = 0;
  bool _won = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _travel = 0;
    _won = false;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _won = true;
    super.acceptGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_won && event is PointerMoveEvent) {
      _travel += event.delta.dx * toStart;
      if (_travel < -4) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }
    }
    super.handleEvent(event);
  }
}
