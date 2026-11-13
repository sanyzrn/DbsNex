import 'package:flutter/widgets.dart';

/// Hands a screen its own route without making the screen rebuild with it.
///
/// `ModalRoute.of(context)` is a dependency on everything about the route,
/// and "is something covering it" is part of that: the element that asked is
/// rebuilt whenever a page, a sheet, a dialog or a menu opens over the route,
/// and again when it closes. Asked from a whole screen — the timeline asked to
/// subscribe to [RouteObserver] — that rebuilt every card on the screen twice
/// for each note opened and closed, about two thousand widgets each way.
///
/// This widget asks instead, from its own small element: it is the one that
/// rebuilds, and it hands back the same [child], so nothing under it does. A
/// screen keeps the route [onRoute] gives it and reads `isCurrent` from that
/// in its callbacks, which never registers a dependency at all.
class NexRouteProbe extends StatefulWidget {
  const NexRouteProbe({super.key, required this.onRoute, required this.child});

  /// Called with this widget's route when it is first known and whenever it
  /// changes — never merely because something was pushed over it.
  final ValueChanged<ModalRoute<Object?>?> onRoute;

  final Widget child;

  @override
  State<NexRouteProbe> createState() => _NexRouteProbeState();
}

class _NexRouteProbeState extends State<NexRouteProbe> {
  ModalRoute<Object?>? _route;
  bool _told = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_told && identical(route, _route)) return;
    _told = true;
    _route = route;
    widget.onRoute(route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
