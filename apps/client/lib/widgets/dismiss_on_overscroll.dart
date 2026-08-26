import 'package:flutter/material.dart';

/// Closes the enclosing route on a downward drag anywhere over [child], once
/// the content is already scrolled to the top.
///
/// A sheet's own drag-to-dismiss only ever sees the header above the scroll
/// view: a plain `SingleChildScrollView` wins the same vertical drag in the
/// gesture arena outright, whether or not it has anywhere left to scroll, so
/// a swipe that starts over the content never reaches it. That is fine on a
/// short sheet, where most of the surface *is* header, and wrong on a long
/// one, where almost none of it is — the note detail sheet for a long note
/// could only be closed from the handle.
///
/// `OverscrollNotification` is what a scroll view reports instead of moving
/// once it is pinned at its own boundary — a negative value is exactly a
/// downward drag past the top — so it stands in for the drag-to-dismiss the
/// content itself cannot forward.
///
/// [OverscrollNotification.dragDetails] is what keeps this to an actual drag
/// at the top: a fast fling from further down can cross the whole scroll
/// range and bounce past the top boundary in one continuous motion, which
/// reports overscroll too, but with `dragDetails: null` — no finger is
/// pressing at that point, the scrollable is just settling its own fling.
/// Without this check that fling closed the sheet on the way to the top
/// instead of merely scrolling it there; only a second, deliberate drag once
/// it has actually arrived should do that.
class NexDismissOnOverscroll extends StatefulWidget {
  const NexDismissOnOverscroll({super.key, required this.child});

  final Widget child;

  @override
  State<NexDismissOnOverscroll> createState() => _NexDismissOnOverscrollState();
}

class _NexDismissOnOverscrollState extends State<NexDismissOnOverscroll> {
  bool _dismissed = false;

  bool _onNotification(OverscrollNotification notification) {
    if (!_dismissed &&
        notification.dragDetails != null &&
        notification.overscroll < -8) {
      _dismissed = true;
      Navigator.of(context).maybePop();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<OverscrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      );
}
