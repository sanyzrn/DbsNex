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

/// What an edge does, where null means "nothing".
///
/// An edge with no action does not move at all, so a user who only wants one
/// gesture is not given a second one they will trigger by accident.

typedef NexSwipeActionResolver = NexSwipeAction? Function({required bool isLeading});

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

/// The fraction of the card's width, from its physical left edge, that a
/// swipe may start from.
const _leadingZone = 0.30;

/// The fraction of the card's width, from its physical right edge, that a
/// swipe may start from — the same fraction as [_leadingZone], so neither
/// edge gets an easier reach than the other. The rest of the card — the
/// middle 40% — starts no swipe at all, which is also exactly the region a
/// long press turns into a drag-to-reorder (see [SwipeableNoteCard]).
const _trailingZone = 0.30;

/// A horizontal drag that yields to a vertical scroll.
///
/// The plain recognizer claims the gesture as soon as horizontal travel passes
/// the touch slop, which a not-quite-vertical flick through a list does all the
/// time — the list would swipe a card open instead of scrolling. This one
/// refuses to enter the arena until the movement is clearly sideways.
class _SidewaysDragRecognizer extends HorizontalDragGestureRecognizer {
  _SidewaysDragRecognizer({
    super.debugOwner,
    required this.widthOf,
    required this.isClosed,
  });

  /// Read at every pointer-down rather than captured once: the recognizer
  /// instance outlives any single `build`, so a closure over the field is the
  /// only way this sees the card's *current* width instead of the width at
  /// the moment the gesture detector was first created.
  final double Function() widthOf;

  /// Whether the card is at rest.
  ///
  /// The zone restriction only applies then. An already-open card is drawn
  /// shifted toward one edge, so "the middle" of the card's original bounds
  /// may now be sitting over content the finger needs to reach to close it —
  /// this only exists to stop a resting card opening by accident, not to make
  /// an open one harder to put back.
  final bool Function() isClosed;

  Offset _travel = Offset.zero;

  @override
  bool isPointerAllowed(PointerEvent event) {
    final width = widthOf();
    if (width > 0 && isClosed()) {
      final dx = event.localPosition.dx;
      if (dx > width * _leadingZone && dx < width * (1 - _trailingZone)) {
        return false;
      }
    }
    return super.isPointerAllowed(event);
  }

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

/// Starts a [SliverReorderableList] drag only for a pointer that lands in the
/// card's middle 40% while the card is at rest — the same zone-gating
/// technique as [_SidewaysDragRecognizer], applied to the standard
/// long-press-to-reorder recognizer instead of a hand-rolled one.
///
/// Gating happens here, not by disabling the listener above it: disabling by
/// zone would have to happen at build time, before the pointer that decides
/// the zone has even landed.
class _MiddleZoneDragRecognizer extends DelayedMultiDragGestureRecognizer {
  _MiddleZoneDragRecognizer({
    super.debugOwner,
    required this.widthOf,
    required this.isClosed,
  });

  final double Function() widthOf;
  final bool Function() isClosed;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (!isClosed()) return false;
    final width = widthOf();
    if (width > 0) {
      final dx = event.localPosition.dx;
      if (dx <= width * _leadingZone || dx >= width * (1 - _trailingZone)) {
        return false;
      }
    }
    return super.isPointerAllowed(event);
  }
}

/// [ReorderableDelayedDragStartListener] wraps the whole item by design — see
/// its own doc comment — so the middle-zone restriction lives in
/// [_MiddleZoneDragRecognizer] rather than in how much of the card this
/// listens on.
class _MiddleZoneReorderListener extends ReorderableDelayedDragStartListener {
  const _MiddleZoneReorderListener({
    required super.child,
    required super.index,
    required this.widthOf,
    required this.isClosed,
  });

  final double Function() widthOf;
  final bool Function() isClosed;

  @override
  MultiDragGestureRecognizer createRecognizer() => _MiddleZoneDragRecognizer(
        debugOwner: this,
        widthOf: widthOf,
        isClosed: isClosed,
      );
}

/// A timeline card that reveals one of its two actions on a swipe.
///
/// Behaviour, in the order the problems appeared:
///
/// * A resting card only starts a swipe from its outer edges — 30% of its
///   width on each side (see [_leadingZone] and [_trailingZone]). The middle
///   used to open on any sideways drag, which is also where a thumb
///   naturally lands while scrolling past a card.
/// * The offset is animated by a spring rather than assigned from the raw
///   pointer delta, so releasing settles instead of snapping.
/// * A gesture cannot cross the middle. Once a direction is picked, dragging
///   back closes the card and stops at zero — it used to sail through and open
///   the *opposite* action, so swiping back from Delete landed on Add Tag.
/// * Dragging most of the way across commits the action on release, the way
///   Mail on iOS does, instead of requiring a second tap on the panel.
/// * Only one card in a list is open at a time, and a scroll closes it.
/// * A long press on the middle zone (see [reorderIndex]) lifts the card for
///   a drag-to-reorder, using [SliverReorderableList]'s own mechanism —
///   releasing without moving reports the same start and end index, which is
///   the list's cue to treat it as a tap-and-hold rather than a reorder.
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
    this.insets = nexCardInsets,
    this.reorderIndex,
  });

  final Widget child;

  /// The margin [child] keeps around itself.
  ///
  /// The action panel is laid out inside the same margin, so it lines up with
  /// the card exactly instead of running past it to the physical screen edge.
  /// Defaults to the timeline card's own gutter.
  final EdgeInsets insets;
  final NexSwipeActionResolver resolveAction;
  final VoidCallback onDelete;
  final VoidCallback onAddTag;
  final String deleteLabel;
  final String addTagLabel;

  /// Off when the user has turned capture haptics off.
  final bool haptics;

  /// Shared across a list so only one card stays open.
  final NexSwipeController? controller;

  /// This card's position in an enclosing [SliverReorderableList].
  ///
  /// Null outside of one — a bare [SwipeableNoteCard] then has no long-press
  /// behaviour at all, only the swipe.
  final int? reorderIndex;

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

  /// Resistance past the point where releasing would run the action.
  ///
  /// It deliberately does *not* start at the resting position: the card has to
  /// travel freely all the way to the commit point, or the rubber band fights
  /// the full swipe and the gesture becomes practically unreachable. Mail
  /// behaves the same way — free until it has committed, firm after.
  double _rubberBand(double value) {
    final limit = _width * _commitFraction;
    if (value.abs() <= limit) return value;
    final overshoot = value.abs() - limit;
    return (value.isNegative ? -1 : 1) * (limit + overshoot * 0.35);
  }

  /// Treated as closed within half a pixel.
  ///
  /// The spring settles *near* zero, not on it, so an exact comparison left a
  /// card that had just closed still claiming a direction — and the wall at
  /// zero then blocked the next swipe the other way entirely.
  bool get _isClosed => _offset.value.abs() < 0.5;

  void _onDragStart(DragStartDetails details) {
    // An open card may only be dragged back toward zero; a closed one takes
    // whichever way the finger goes first.
    _allowedSign = _isClosed ? 0 : (_offset.value.isNegative ? -1 : 1);
    _passedCommit = false;
    _offset.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    var next = _offset.value + details.delta.dx;

    if (_allowedSign == 0) {
      // An edge bound to no action simply does not open.
      if (next != 0 && !_edgeIsLive(next)) return;
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
    if (current != 0 && current.abs() >= _width * _commitFraction) {
      final revealed = _actionFor(current);
      if (revealed != null) {
        _run(revealed);
        return;
      }
    }

    final flung = velocity.abs() > 420 &&
        (velocity.isNegative == current.isNegative) &&
        current != 0;
    final shouldOpen =
        _edgeIsLive(current) && (flung || current.abs() >= _open * 0.55);
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

  /// Whether the edge the finger is heading for does anything at all.
  bool _edgeIsLive(double dx) {
    if (dx == 0) return true;
    final leading = _rtl ? dx < 0 : dx > 0;
    return widget.resolveAction(isLeading: leading) != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        Widget card = Semantics(
          customSemanticsActions: {
            CustomSemanticsAction(label: widget.deleteLabel): widget.onDelete,
            CustomSemanticsAction(label: widget.addTagLabel): widget.onAddTag,
          },
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _SidewaysDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<_SidewaysDragRecognizer>(
                () => _SidewaysDragRecognizer(
                  debugOwner: this,
                  widthOf: () => _width,
                  isClosed: () => _isClosed,
                ),
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
                        // The same gutter the card keeps, so the panel starts
                        // where the card starts and the two look like one
                        // object rather than a card floating over a bar.
                        child: Padding(
                          padding: widget.insets,
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
                              // Past the commit point the panel says so, so the
                              // user knows letting go will act rather than open.
                              committed: dx.abs() >= _width * _commitFraction,
                              theme: theme,
                              onPressed: () => _run(revealed),
                            ),
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

        final reorderIndex = widget.reorderIndex;
        if (reorderIndex != null) {
          card = _MiddleZoneReorderListener(
            index: reorderIndex,
            widthOf: () => _width,
            isClosed: () => _isClosed,
            child: card,
          );
        }
        return card;
      },
    );
  }
}

/// Below this width the panel is a bare capsule: there is no room for a glyph,
/// and a squeezed one reads as a rendering fault rather than as a control.
const _glyphRevealWidth = 54.0;

/// The coloured surface behind a swiped card.
///
/// A capsule, at every width. It starts as a narrow vertical pill against the
/// card's own edge and widens into a lozenge as the finger travels — the same
/// shape throughout, never a rectangle bleeding off the side of the screen.
class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.width,
    required this.action,
    required this.label,
    required this.committed,
    required this.theme,
    required this.onPressed,
  });

  final double width;
  final NexSwipeAction action;
  final String label;
  final bool committed;
  final ThemeData theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final destructive = action == NexSwipeAction.delete;
    final background =
        destructive ? NexColors.swipeDelete : NexColors.swipeAddTag;
    final showGlyph = width >= _glyphRevealWidth;
    return SizedBox(
      width: width,
      child: Material(
        color: background,
        // Maximum rounding at any size: StadiumBorder takes half the shorter
        // side, so a narrow panel is a vertical pill and a wide one a lozenge.
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: AnimatedScale(
              scale: showGlyph ? 1 : 0.4,
              duration: NexMotion.standard,
              curve: NexMotion.curve,
              child: AnimatedOpacity(
                opacity: showGlyph ? 1 : 0,
                duration: NexMotion.standard,
                curve: NexMotion.curve,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionGlyph(
                      icon: destructive
                          ? Icons.delete_outline
                          : Icons.label_outline,
                      committed: committed,
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

/// The panel's icon, which reacts when the swipe locks in.
///
/// Crossing the commit point is the one moment in the gesture with a real
/// consequence — let go here and the action runs — and until now the only sign
/// of it was a static 12% scale step. The icon now takes a beat: it swells,
/// tips, and springs back, so the change of state is something the hand feels
/// it caused rather than something the eye has to notice.
class _ActionGlyph extends StatefulWidget {
  const _ActionGlyph({required this.icon, required this.committed});

  final IconData icon;
  final bool committed;

  @override
  State<_ActionGlyph> createState() => _ActionGlyphState();
}

class _ActionGlyphState extends State<_ActionGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.35)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.35, end: 1.12)
          .chain(CurveTween(curve: Curves.elasticOut)),
      weight: 70,
    ),
  ]).animate(_pop);

  /// A quick tip and back. Small on purpose: a full spin would be a mascot.
  late final Animation<double> _tilt = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: -0.26)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(begin: -0.26, end: 0.12)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.12, end: 0.0)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 40,
    ),
  ]).animate(_pop);

  @override
  void didUpdateWidget(_ActionGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.committed == oldWidget.committed) return;
    if (!widget.committed) {
      // Dragged back below the line: settle, rather than play the pop in
      // reverse, which would read as a second event.
      _pop.animateTo(0, duration: NexMotion.fast, curve: NexMotion.curve);
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _pop.value = 1;
      return;
    }
    _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _pop,
        child: Icon(widget.icon, color: Colors.white, size: 22),
        builder: (context, child) => Transform.rotate(
          angle: _tilt.value,
          child: Transform.scale(scale: _scale.value, child: child),
        ),
      );
}
