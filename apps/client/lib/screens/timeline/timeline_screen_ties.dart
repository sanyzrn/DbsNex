part of '../timeline_screen.dart';

extension _TimelineScreenTies on TimelineScreenState {
  void _onSwipeChanged() {
    if (_swipe.openCard != null) {
      _guard.open(_swipe, close: _swipe.closeAll);
    } else {
      _guard.closed(_swipe);
    }
  }

  void _fadeInBody() {
    _searchFade.duration = NexMotion.of(context, NexMotion.enter);
    unawaited(_searchFade.forward(from: 0).whenComplete(_dissolve.clear));
  }

  void _onSearchChanged() {
    if (mounted) _rebuild(() {});
  }

  Future<void> _loadTimeline() async {
    // Both sides of this matter and neither replaces the other: the model's
    // failure state is what a read that never returns needs, and the tour
    // check is what a read that *does* return can make due.
    final loaded = await _model.load();
    if (!mounted || loaded == null) return;
    _requestAiHeader(loaded);
    _tourWhenReady();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => NexMetrics.shared.recordTimelineShown(),
    );
  }

  void _onModelChanged() => _onModelChange();
}
