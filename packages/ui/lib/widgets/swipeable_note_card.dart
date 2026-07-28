import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
// CustomSemanticsAction lives in the semantics library; material re-exports
// neither it nor SemanticsAction, so the swipe actions had no accessible
// equivalent and the file did not compile.
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../tokens/nex_tokens.dart';

enum NexSwipeAction { delete, addTag }

typedef NexSwipeActionResolver = NexSwipeAction Function({required bool isLeading});

/// Keeps at most one card open across a list.
///
/// Without it every card that had been swiped stayed open behind the one the
/// user was looking at, and nothing closed them — not scrolling, not tapping
/// elsewhere. The timeline creates one and closes it on scroll and on a tap
/// outside any card.
class NexSwipeController extends ChangeNotifier {
  Object? _open;

  Object? get openCard => _open;

  void opened(Object card) {
    if (identical(_open, card)) return;
    _open = card;
    notifyListeners();
  }

  void closed(Object card) {
    if (!identical(_open, card)) return;
    _open = null;
    notifyListeners();
  }

  /// Closes whatever is open. Safe to call when nothing is.
  void closeAll() {
    if (_open == null) return;
    _open = null;
    notifyListeners();
  }
}

/// A horizontal drag that yields to a vertical scroll.
///
/// The plain recognizer claims the gesture as soon as horizontal travel passes
/// the touch slop, which a not-quite-vertical flick through a list does all the
/// time — the list would swipe a card open instead of scrolling. This one
/// refuses to enter the arena until the movement is clearly sideways.
class _SidewaysDragRecognizer extends HorizontalDragGestureRecognizer {
  _SidewaysDragRecognizer({super.debugOwner});

  Offset _travel = Offset.zero;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _travel += event.delta;
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _travel = Offset.zero;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    if (_travel.dx.abs() < _travel.dy.abs() * 1.6) return false;
    return super.hasSufficientGlobalDistanceToAccept(
      pointerDeviceKind,
      deviceTouchSlop,
    );
  }
}

/// A timeline card that reveals one of its two actions on a swipe.
///
/// Behaviour, in the order the problems appeared:
///
/// * The offset is animated by a spring rather than assigned from the raw
///   pointer delta, so releasing settles instead of snapping.
/// * A gesture cannot cross the middle. Once a direction is picked, dragging
///   back closes the card and stops at zero — it used to sail through and open
///   the *opposite* action, so swiping back from Delete landed on Add Tag.
/// * Dragging most of the way across commits the action on release, the way
///   Mail on iOS does, instead of requiring a second tap on the panel.
/// * Only one card in a list is open at a time, and a scroll closes it.
class SwipeableNoteCard extends StatefulWidget {
  const SwipeableNoteCard({
    super.key,
    required this.child,
    required this.resolveAction,
    required this.onDelete,
    required this.onAddTag,
    required this.deleteLabel,
    required this.addTagLabel,
    this.haptics = true,
    this.controller,
  });

  final Widget child;
  final NexSwipeActionResolver resolveAction;
  final VoidCallback onDelete;
  final VoidCallback onAddTag;
  final String deleteLabel;
  final String addTagLabel;

  /// Off when the user has turned capture haptics off.
  final bool haptics;

  /// Shared across a list so only one card stays open.
  final NexSwipeController? controller;

  @override
  State<SwipeableNoteCard> createState() => _SwipeableNoteCardState();
}

/// Past this fraction of the card's width, releasing runs the action outright.
const _commitFraction = 0.62;

class _SwipeableNoteCardState extends State<SwipeableNoteCard>
    with SingleTickerProviderStateMixin {
  /// Unbounded: the drag is allowed to overshoot the stop so it can rubber-band.
  late final AnimationController _offset =
      AnimationController.unbounded(vsync: this, value: 0);

  double _width = 0;
  double get _open => _width * 0.45;

  /// The sign the current gesture is allowed to move in. Locked on drag start
  /// so one drag can never travel from one action to the other.
  int _allowedSign = 0;
  bool _passedCommit = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(SwipeableNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _offset.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller == null) return;
    // Something else opened, or the list asked everyone to close.
    if (!identical(controller.openCard, this) && _offset.value != 0) _close();
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  String _label(NexSwipeAction action) =>
      action == NexSwipeAction.delete ? widget.deleteLabel : widget.addTagLabel;

  void _tick() {
    if (widget.haptics) HapticFeedback.selectionClick();
  }

  void _run(NexSwipeAction action) {
    if (widget.haptics) HapticFeedback.mediumImpact();
    _close();
    action == NexSwipeAction.delete ? widget.onDelete() : widget.onAddTag();
  }

  /// Past the stop the card keeps moving, but at a fraction of the finger —
  /// the same resistance iOS uses to say "this is as far as it goes".
  double _rubberBand(double value) {
    final limit = _open;
    if (value.abs() <= limit) return value;
    final overshoot = value.abs() - limit;
    return (value.isNegative ? -1 : 1) * (limit + overshoot * 0.4);
  }

  void _onDragStart(DragStartDetails details) {
    // An open card may only be dragged back toward zero; a closed one takes
    // whichever way the finger goes first.
    _allowedSign = _offset.value == 0 ? 0 : (_offset.value.isNegative ? -1 : 1);
    _passedCommit = false;
    _offset.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    var next = _offset.value + details.delta.dx;

    if (_allowedSign == 0) {
      if (next != 0) _allowedSign = next.isNegative ? -1 : 1;
    } else {
      // The wall at zero. Dragging back from an open card closes it and stops
      // there rather than continuing into the other action.
      next = _allowedSign > 0 ? next.clamp(0.0, double.infinity) : next.clamp(double.negativeInfinity, 0.0);
    }

    _offset.value = _rubberBand(next);

    final committed = _offset.value.abs() >= _width * _commitFraction;
    if (committed != _passedCommit) {
      _passedCommit = committed;
      if (committed) _tick();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final current = _offset.value;

    // Dragged most of the way across: run it, the way Mail does.
    if (current.abs() >= _width * _commitFraction) {
      final revealed = _actionFor(current);
      if (revealed != null) {
        _run(revealed);
        return;
      }
    }

    final flung = velocity.abs() > 420 &&
        (velocity.isNegative == current.isNegative) &&
        current != 0;
    final shouldOpen = flung || current.abs() >= _open * 0.55;
    final sign = current.isNegative ? -1 : 1;
    _settle(shouldOpen ? sign * _open : 0, velocity);
  }

  void _settle(double target, double velocity) {
    _passedCommit = false;
    _allowedSign = 0;
    if (!mounted) {
      _offset.value = target;
      return;
    }
    if (target == 0) {
      widget.controller?.closed(this);
    } else {
      widget.controller?.opened(this);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _offset.value = target;
      return;
    }
    _offset.animateWith(
      SpringSimulation(
        // Critically damped: it arrives quickly and never wobbles, which is
        // what a list row should do. A bouncier spring reads as a toy.
        const SpringDescription(mass: 1, stiffness: 500, damping: 42),
        _offset.value,
        target,
        velocity,
      ),
    );
  }

  void _close() => _settle(0, 0);

  /// Which action a given offset has uncovered, in either script direction.
  NexSwipeAction? _actionFor(double dx) {
    if (dx.abs() < 0.5) return null;
    final leading = _rtl ? dx < 0 : dx > 0;
    return widget.resolveAction(isLeading: leading);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return Semantics(
          customSemanticsActions: {
            CustomSemanticsAction(label: widget.deleteLabel): widget.onDelete,
            CustomSemanticsAction(label: widget.addTagLabel): widget.onAddTag,
          },
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _SidewaysDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<_SidewaysDragRecognizer>(
                () => _SidewaysDragRecognizer(debugOwner: this),
                (instance) => instance
                  ..onStart = _onDragStart
                  ..onUpdate = _onDragUpdate
                  ..onEnd = _onDragEnd
                  ..onCancel = _close,
              ),
            },
            child: AnimatedBuilder(
              animation: _offset,
              builder: (context, child) {
                final dx = _offset.value;
                // The spring settles to within a tolerance of zero rather than
                // exactly zero, so an equality test here would leave a
                // sub-pixel panel — and its label — alive in the tree forever.
                final revealed = _actionFor(dx);
                return Stack(
                  children: [
                    // Built only while open, so a closed card cannot leak its
                    // action labels into the widget tree, the semantics tree,
                    // or a hit test.
                    if (revealed != null)
                      Positioned.fill(
                        child: Align(
                          // Physical, not directional: whichever way the card
                          // actually moved is the side the space opened on.
                          alignment: dx > 0
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: _ActionPanel(
                            width: dx.abs(),
                            action: revealed,
                            label: _label(revealed),
                            progress: (dx.abs() / (_open == 0 ? 1 : _open))
                                .clamp(0.0, 1.0),
                            // Past the commit point the panel says so, so the
                            // user knows letting go will act rather than open.
                            committed: dx.abs() >= _width * _commitFraction,
                            theme: theme,
                            onPressed: () => _run(revealed),
                          ),
                        ),
                      ),
                    Transform.translate(offset: Offset(dx, 0), child: child),
                  ],
                );
              },
              // Passed through the builder so the card's own subtree is never
              // rebuilt while the offset animates.
              child: RepaintBoundary(child: widget.child),
            ),
          ),
        );
      },
    );
  }
}

/// The coloured surface behind a swiped card.
class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.width,
    required this.action,
    required this.label,
    required this.progress,
    required this.committed,
    required this.theme,
    required this.onPressed,
  });

  final double width;
  final NexSwipeAction action;
  final String label;
  final double progress;
  final bool committed;
  final ThemeData theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final destructive = action == NexSwipeAction.delete;
    final background =
        destructive ? NexColors.swipeDelete : NexColors.swipeAddTag;
    return SizedBox(
      width: width,
      child: Material(
        color: background,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Opacity(
              // The label only becomes readable once there is room for it.
              opacity: ((progress - 0.25) / 0.45).clamp(0.0, 1.0),
              child: AnimatedScale(
                // A small kick at the commit point: the panel confirms that
                // letting go now performs the action.
                scale: committed ? 1.12 : 0.85 + 0.15 * progress,
                duration: NexMotion.fast,
                curve: NexMotion.curve,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      destructive ? Icons.delete_outline : Icons.label_outline,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
