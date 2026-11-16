part of '../timeline_screen.dart';

/// What the list's own movement does to the screen around it: the scroll
/// tick, the window of notes, the day chip, and the dock stepping back.
/// Split out of timeline_screen.dart, which was at the size limit.
extension _TimelineScroll on TimelineScreenState {
  bool _onScroll(ScrollNotification notification) {
    // The timeline's own scroll only: the tag row's horizontal scroll bubbles
    // through the viewport with a depth above zero, and its metrics are not
    // the list's — a horizontal drag used to tick, trim and re-name the
    // sticky day as though the notes had moved.
    if (notification.depth != 0) return false;
    // A scroll that has come to rest near the top, however it got there.
    if (notification is ScrollEndNotification &&
        notification.metrics.pixels < TimelineScreenState._trimBelow &&
        !_searching) {
      _model.trimWindow();
    }
    if (notification is! ScrollUpdateNotification) return false;
    _queueStickyDay();
    _followDock(notification);
    final offset = notification.metrics.pixels;
    // Back within a few screens of the top: the depth scrolled earlier is no
    // longer needed, so it stops costing every change a full re-read.
    // Only for a finger moving it up: a scroll the app starts itself (to a
    // reminder's note, say) passes through here on its way down.
    if (offset < TimelineScreenState._trimBelow &&
        !_searching &&
        notification.dragDetails != null &&
        (notification.scrollDelta ?? 0) < 0) {
      _model.trimWindow();
    }
    final travelled = (offset - _lastTickOffset).abs();
    if (travelled < TimelineScreenState._scrollTickDistance) return false;
    // A jump this large is not a finger — it is the list being replaced
    // under one, which happens every time search opens or a filter changes.
    // Re-anchor silently rather than buzzing at a scroll nobody performed.
    final jumped = travelled > TimelineScreenState._scrollTickDistance * 8;
    _lastTickOffset = offset;
    if (!jumped) nexTick();
    return false;
  }

  /// Grows the timeline window when the list is close to its end.
  ///
  /// Not while searching — search results are their own query, not
  /// [NexServices.loadMoreTimeline]'s window.
  void _maybeLoadMore() {
    if (_searching || !_rowsCache.grows) return;
    _model.loadMore();
  }

  /// Below this the dock is always whole: the top of the home screen is
  /// where its destinations are looked for.
  static const _dockWholeAbove = 120.0;

  /// A finger has to carry the list this far down before the destinations
  /// step back, and this far back up before they return — less, because
  /// turning round is the plainer signal.
  static const _dockAwayAfter = 48.0;
  static const _dockBackAfter = 24.0;

  /// Steps the dock's four destinations back while someone reads down the
  /// list, and brings them back the moment they turn round (2.8.0).
  ///
  /// The bar and the fade behind it cover the bottom fifth of the screen,
  /// which is a fifth of every note being read. Capture stays exactly where
  /// it is — the one thing on this screen that must never move — and the
  /// other four are a short pull away: back up a little, at the top, at the
  /// end of the list.
  ///
  /// Only a finger steps them back. A scroll the app starts itself — to a
  /// reminder's note, back to the top for a search — is not reading.
  void _followDock(ScrollUpdateNotification notification) {
    final metrics = notification.metrics;
    if (metrics.pixels < _dockWholeAbove ||
        metrics.extentAfter <= 0 ||
        _selecting ||
        _searching) {
      _dockTravel = 0;
      _setDockAway(false);
      return;
    }
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return;
    if (delta.sign != _dockTravel.sign) _dockTravel = 0;
    _dockTravel += delta;
    if (_dockTravel >= _dockAwayAfter && notification.dragDetails != null) {
      _setDockAway(true);
    } else if (_dockTravel <= -_dockBackAfter) {
      _setDockAway(false);
    }
  }

  /// Steps the destinations back, or returns them. Says so once, when it
  /// changes: the scroll that asks does so on every frame.
  void _setDockAway(bool away) {
    if (_dockAway.value == away || !mounted) return;
    // Someone finding their way by touch or by a switch gets a dock that
    // stays where it was found.
    if (away && MediaQuery.accessibleNavigationOf(context)) return;
    _dockAway.value = away;
    _dockRecede
      ..duration = NexMotion.of(context, NexMotion.exit)
      ..reverseDuration = NexMotion.of(context, NexMotion.enter);
    if (away) {
      unawaited(_dockRecede.forward());
    } else {
      unawaited(_dockRecede.reverse());
    }
  }
}
