part of '../timeline_screen.dart';

/// The timeline's floating dock, hidden while a keyboard is up.
///
/// The keyboard dependency lives here, in the FAB slot, rather than in
/// `_screen`. Asking for `viewInsetsOf` in the screen rebuilt its whole tree —
/// the scroll view, every sliver, the header, the filter row and the rail —
/// on each frame of the keyboard's open or close animation. A leaf that only
/// returns the dock or nothing keeps that animation to one small subtree.
class _TimelineDockSlot extends StatelessWidget {
  const _TimelineDockSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom > 0
      ? const SizedBox.shrink()
      : child;
}
