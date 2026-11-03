part of 'nex_pull_refresh.dart';

/// A local bridge between the pull strip and its own Scrollable. It changes
/// no platform/global physics and releases unused reverse travel immediately.
class NexPullRefreshController {
  _NexPullRefreshState? _owner;

  ScrollPhysics physics({ScrollPhysics? parent}) =>
      _NexPullPhysics(this, parent: parent);

  double get extent => _owner?._offset.value ?? 0;

  double _consume(ScrollMetrics position, double delta) {
    final owner = _owner;
    if (owner == null ||
        owner._cancelledGesture ||
        owner._pointers.length > 1 ||
        owner._mode == _Mode.refreshing ||
        owner._mode == _Mode.done) {
      return delta;
    }
    if (delta < 0 && owner._drag > 0) {
      final used = math.min(owner._drag, -delta);
      owner._move(math.max(0, owner._drag - used));
      return delta + used;
    }
    return delta;
  }
}

class _NexPullPhysics extends ScrollPhysics {
  const _NexPullPhysics(this.control, {super.parent});
  final NexPullRefreshController control;

  @override
  _NexPullPhysics applyTo(ScrollPhysics? ancestor) =>
      _NexPullPhysics(control, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final remainder = control._consume(position, offset);
    return remainder == 0
        ? 0
        : super.applyPhysicsToUserOffset(position, remainder);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // Nex draws its own top overscroll; a native bouncing offset would consume
    // the same travel twice. Bottom/platform behavior stays with the parent.
    if (control._owner != null &&
        value < position.minScrollExtent &&
        position.pixels >= position.minScrollExtent) {
      return value - position.minScrollExtent;
    }
    return super.applyBoundaryConditions(position, value);
  }
}
