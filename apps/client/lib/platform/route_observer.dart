import 'package:flutter/material.dart';

/// The app's one route observer.
///
/// A screen that needs to know it has been covered and then uncovered again
/// subscribes to this. There is exactly one because a `RouteObserver` only
/// reports routes pushed onto the navigator it is installed on, and a second
/// one installed elsewhere would silently report nothing.
///
/// Typed on `ModalRoute` rather than `PageRoute` so a bottom sheet counts:
/// opening Settings over the timeline and coming back is leaving and
/// returning by any reading a person would give those words.
final nexRouteObserver = RouteObserver<ModalRoute<void>>();
