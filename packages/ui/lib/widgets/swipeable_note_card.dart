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

/// A timeline card that reveals one of the two ADR-022 actions on a swipe.
///
/// The offset is driven by an [AnimationController] rather than by `setState`
/// on the raw pointer delta. The old version snapped between 0 and open with
/// no interpolation at all and had no rubber-band past the stop, which is what
/// made the gesture feel stiff. Releasing now settles on a spring, and a fling
/// carries its velocity into that spring instead of being discarded.
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
  });

  final Widget child;
  final NexSwipeActionResolver resolveAction;
  final VoidCallback onDelete;
  final VoidCallback onAddTag;
  final String deleteLabel;
  final String addTagLabel;

  /// Off when the user has turned capture haptics off.
  final bool haptics;

  @override
  State<SwipeableNoteCard> createState() => _SwipeableNoteCardState();
}

class _SwipeableNoteCardState extends State<SwipeableNoteCard>
    with SingleTickerProviderStateMixin {
  /// Unbounded: the drag is allowed to overshoot the stop so it can rubber-band.
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  double _open = 0;
  bool _passedThreshold = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  String _label(NexSwipeAction action) =>
      action == NexSwipeAction.delete ? widget.deleteLabel : widget.addTagLabel;

  void _run(NexSwipeAction action) {
    if (widget.haptics) HapticFeedback.mediumImpact();
    _close();
    action == NexSwipeAction.delete ? widget.onDelete() : widget.onAddTag();
  }

  /// Past the stop the card keeps moving, but at a fraction of the finger —
  /// the same resistance iOS uses to say "this is as far as it goes".
  double _rubberBand(double value) {
    if (value.abs() <= _open) return value;
    final overshoot = value.abs() - _open;
    return (value.isNegative ? -1 : 1) * (_open + overshoot * 0.28);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = _rubberBand(_offset.value + details.delta.dx);
    _offset.value = next;

    // One tick when the card crosses the point where releasing would open it,
    // so the threshold is felt rather than guessed at.
    final past = next.abs() >= _open * 0.6;
    if (past != _passedThreshold) {
      _passedThreshold = past;
      if (past && widget.haptics) HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final current = _offset.value;

    // A deliberate fling opens even from a short drag; otherwise the distance
    // decides. `nexSwipeThreshold` stays the resting contract (ADR-022).
    final flung = velocity.abs() > 420;
    final direction = flung ? (velocity.isNegative ? -1 : 1) : (current.isNegative ? -1 : 1);
    final shouldOpen =
        flung || current.abs() >= _open * (nexSwipeThreshold / 0.45);

    _settle(shouldOpen ? direction * _open : 0, velocity);
  }

  void _settle(double target, double velocity) {
    _passedThreshold = false;
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _open = constraints.maxWidth * 0.45;
        final leading = widget.resolveAction(isLeading: true);
        final trailing = widget.resolveAction(isLeading: false);
        return Semantics(
          customSemanticsActions: {
            CustomSemanticsAction(label: widget.deleteLabel): widget.onDelete,
            CustomSemanticsAction(label: widget.addTagLabel): widget.onAddTag,
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () async {
              if (widget.haptics) HapticFeedback.mediumImpact();
              final selected = await showMenu<NexSwipeAction>(
                context: context,
                position: const RelativeRect.fromLTRB(24, 160, 24, 0),
                items: [
                  PopupMenuItem(value: leading, child: Text(_label(leading))),
                  PopupMenuItem(value: trailing, child: Text(_label(trailing))),
                ],
              );
              if (selected != null) _run(selected);
            },
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: _close,
            child: AnimatedBuilder(
              animation: _offset,
              builder: (context, child) {
                final dx = _offset.value;
                // Which action the current offset has uncovered, if any. The
                // spring settles to within a tolerance of zero rather than
                // exactly zero, so an equality test here would leave a
                // sub-pixel panel — and its label — alive in the tree forever.
                final revealed = dx.abs() < 0.5
                    ? null
                    : ((_rtl ? dx < 0 : dx > 0) ? leading : trailing);
                return Stack(
                  children: [
                    // Built only while open, so a closed card cannot leak its
                    // action labels into the widget tree, the semantics tree,
                    // or a hit test.
                    if (revealed != null)
                      Positioned.fill(
                        child: Align(
                          // Physical, not directional: whichever way the card
                          // actually moved is the side the space opened on, in
                          // either script direction.
                          alignment: dx > 0
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: _ActionPanel(
                            width: dx.abs(),
                            action: revealed,
                            label: _label(revealed),
                            // Fades and scales in as the card moves, so the
                            // action arrives with the gesture rather than
                            // popping into place.
                            progress:
                                (dx.abs() / (_open == 0 ? 1 : _open)).clamp(0.0, 1.0),
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
    required this.theme,
    required this.onPressed,
  });

  final double width;
  final NexSwipeAction action;
  final String label;
  final double progress;
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
              child: Transform.scale(
                scale: 0.85 + 0.15 * progress,
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
