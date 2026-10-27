import 'package:flutter/material.dart';

/// Present above the Navigator when the app runs in a wide window
/// (`docs/27-desktop.md`).
///
/// The shell that draws the left rail puts it there, once. Everything that
/// behaves differently on a desktop asks [NexDesktopScope.maybeOf] instead of
/// measuring the window itself: a page keeps to [contentWidth] and fades in
/// instead of sliding, a sheet opens as a centred panel. Below the scope the
/// window size already is the content area's, so a width check there would
/// answer for the wrong thing.
class NexDesktopScope extends InheritedWidget {
  const NexDesktopScope({
    super.key,
    this.enabled = true,
    this.contentWidth = nexDesktopContentWidth,
    required super.child,
  });

  /// Whether the window is wide enough. The scope is always in the tree, so
  /// resizing across the breakpoint does not rebuild what is below it from
  /// scratch; it only changes the answer.
  final bool enabled;

  /// The widest a page that reads (settings, lists, a note) is allowed to be.
  final double contentWidth;

  static NexDesktopScope? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<NexDesktopScope>();
    return scope != null && scope.enabled ? scope : null;
  }

  /// Whether this part of the tree is a desktop layout.
  static bool isDesktop(BuildContext context) => maybeOf(context) != null;

  @override
  bool updateShouldNotify(NexDesktopScope old) =>
      enabled != old.enabled || contentWidth != old.contentWidth;
}

/// The widest a reading page gets on a desktop.
const nexDesktopContentWidth = 880.0;

/// Keeps [child] to [width] and centres it; the sides show the app's own
/// background, so a page that is narrower than the window reads as a sheet of
/// paper on a desk rather than a stretched phone screen.
class NexDesktopPage extends StatelessWidget {
  const NexDesktopPage({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}
