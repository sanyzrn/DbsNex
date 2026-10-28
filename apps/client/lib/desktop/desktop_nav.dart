import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../modules/module_rollout.dart' show nexDesktopPlatform;

/// The places the left rail goes to (`docs/27-desktop.md`).
enum NexSection { notes, recurring, library, tools, settings }

/// A window at least this wide gets the desktop layout. A narrow desktop
/// window and the tests' 800 × 600 stay on the phone's.
const nexDesktopMinWidth = 1000.0;

/// Whether this window gets the desktop layout: a desktop platform, and wide
/// enough. A phone, a tablet in landscape and a large foldable always keep
/// the phone's layout — the desktop one has no swipe actions or edge
/// swipe-back, and switching between the two on every rotation is not a
/// change an Android update should bring unannounced.
bool nexWideWindow(double width) =>
    nexDesktopPlatform && width >= nexDesktopMinWidth;

/// Owns the root Navigator's key and watches its stack, so the rail knows
/// which section the person is in and whether a dialog is covering it.
///
/// A section is a page pushed on the home screen. Going to another one pops
/// back to home first, so the stack never grows by sections: home, one
/// section, whatever that section opens.
class NexDesktopNav extends NavigatorObserver with ChangeNotifier {
  NexDesktopNav({required this.pageFor, this.onReturn});

  /// The page a section shows; null for [NexSection.notes], which is home.
  final WidgetBuilder? Function(NexSection section) pageFor;

  /// Called when a section's page closes, so the timeline catches up with
  /// what was changed there — what the phone's dock does when its pages
  /// close (a note restored from Trash, a recurring item added).
  final void Function(NexSection section)? onReturn;

  final navigatorKey = GlobalKey<NavigatorState>();

  NexSection _section = NexSection.notes;
  NexSection get section => _section;

  Route<dynamic>? _top;

  /// Whether a dialog, menu or sheet is open. The rail waits for it rather
  /// than navigating underneath it.
  bool get covered => _top != null && _top is! PageRoute;

  void go(NexSection target) {
    final navigator = navigatorKey.currentState;
    if (navigator == null || covered) return;
    // A page that refuses to close — a backup running, an entry being
    // edited — stays, as it would for Back or Esc; popUntil would have torn
    // it down without asking.
    while (navigator.canPop()) {
      if (_top?.popDisposition == RoutePopDisposition.doNotPop) return;
      navigator.pop();
    }
    _set(target);
    final page = pageFor(target);
    if (page != null) {
      unawaited(
        navigator
            .push<void>(NexPageRoute<void>(builder: page))
            .then((_) => onReturn?.call(target)),
      );
    }
  }

  void _set(NexSection value) {
    if (_section == value) return;
    _section = value;
    notifyListeners();
  }

  // The navigator calls these while it builds; listeners are told after.
  void _settle(Route<dynamic>? top) {
    _top = top;
    if (top == null || top.isFirst) _set(NexSection.notes);
    Future.microtask(notifyListeners);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _settle(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _settle(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _settle(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _settle(newRoute);
}
