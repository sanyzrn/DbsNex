import 'package:flutter/widgets.dart';

/// Who is open inside a [NexTapGuard], and how to close it (W4.5).
///
/// One rule for every surface that opens over the content it belongs to — a
/// card's hold menu, a card swiped to show its actions, anything added later:
/// **while one is open, the first tap closes it and does nothing else**,
/// including a tap on the thing that opened it.
///
/// The 1.80.x series fixed that rule three times, once per surface: a tap
/// outside the hold menu went on to open another note; a tap on the card that
/// owned the menu opened the note under it; a tap meant to put a swiped card
/// away also folded the date group beside it. Each fix was local. This is the
/// one place the rule now lives.
///
/// Only one thing is open at a time: opening a second closes the first.
class NexTapGuardController extends ChangeNotifier {
  Object? _owner;
  VoidCallback? _close;

  /// Whether something is open, so a tap now belongs to closing it.
  bool get isOpen => _owner != null;

  /// What is open, or null.
  Object? get owner => _owner;

  /// [owner] has opened; [close] puts it away.
  void open(Object owner, {required VoidCallback close}) {
    if (identical(_owner, owner)) {
      _close = close;
      return;
    }
    final previous = _close;
    _owner = owner;
    _close = close;
    previous?.call();
    notifyListeners();
  }

  /// [owner] has closed by itself. Ignored if something else is open.
  void closed(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _close = null;
    notifyListeners();
  }

  /// Hands a tap to the rule: if something is open, closes it and returns
  /// true — the caller then does nothing else with the tap. False when
  /// nothing was open and the tap is the caller's to use.
  bool claim() {
    final close = _close;
    if (_owner == null) return false;
    _owner = null;
    _close = null;
    notifyListeners();
    close?.call();
    return true;
  }
}

/// Puts a [NexTapGuardController] in scope for everything below it.
///
/// A screen wraps its content in one. Surfaces that open register with it
/// ([NexTapGuardController.open]); controls that must not act while something
/// is open are wrapped in [NexTapGuarded].
class NexTapGuard extends StatefulWidget {
  const NexTapGuard({super.key, this.controller, required this.child});

  /// Supplied when the screen needs to ask the guard itself — for its app bar
  /// or floating button, say. Otherwise the guard makes its own.
  final NexTapGuardController? controller;
  final Widget child;

  /// The nearest guard's controller, or null when there is none.
  static NexTapGuardController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NexTapGuardScope>()?.notifier;

  @override
  State<NexTapGuard> createState() => _NexTapGuardState();
}

class _NexTapGuardState extends State<NexTapGuard> {
  NexTapGuardController? _own;

  NexTapGuardController get _controller =>
      widget.controller ?? (_own ??= NexTapGuardController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _NexTapGuardScope(notifier: _controller, child: widget.child);
}

class _NexTapGuardScope extends InheritedNotifier<NexTapGuardController> {
  const _NexTapGuardScope({required super.notifier, required super.child});
}

/// Makes [child] inert while something in the guard is open: a tap on it
/// closes that thing and reaches nothing inside [child].
///
/// Wrapping is structural, so a control added later inherits the rule rather
/// than having to remember it. Drags are left alone — a list under a guarded
/// child still scrolls.
///
/// [controller] overrides the one in scope; with neither, [child] is returned
/// as it is.
class NexTapGuarded extends StatelessWidget {
  const NexTapGuarded({super.key, this.controller, required this.child});

  final NexTapGuardController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final guard = controller ?? NexTapGuard.maybeOf(context);
    if (guard == null) return child;
    return ListenableBuilder(
      listenable: guard,
      builder: (context, child) {
        final open = guard.isOpen;
        return GestureDetector(
          // Opaque only while open, so that is the only time this takes a
          // tap from anything behind it.
          behavior: open
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          onTap: open ? guard.claim : null,
          // Absorbing, not ignoring: the tap has been spent on closing, and
          // must not also press whatever is inside.
          child: AbsorbPointer(absorbing: open, child: child),
        );
      },
      child: child,
    );
  }
}
