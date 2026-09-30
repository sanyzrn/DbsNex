import 'dart:async';

import 'package:flutter/material.dart';

import 'package:nex_ui/nex_ui.dart';

import 'nex_card_opening.dart';

export 'nex_card_opening.dart' show NexSheetOrigin;

/// Wraps dialog content at a stable width.
///
/// `AlertDialog` sizes itself to its content's intrinsic width, so a dialog
/// holding a text field started as a narrow box and widened with every word
/// typed into it. Every dialog in the app is the same width now, capped so it
/// does not stretch across a desktop window.
class NexDialogBody extends StatelessWidget {
  const NexDialogBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      // maxFinite lets the dialog take the width its own constraints allow,
      // which is the platform's dialog width rather than the content's.
      width: width < 420 ? double.maxFinite : 380,
      child: child,
    );
  }
}

/// Opens a bottom sheet the way every bottom sheet in Nex opens.
///
/// The nine call sites had drifted into nine different presentations: some
/// declared `useSafeArea`, some wrapped a `SafeArea` by hand inside the
/// builder, and the tag merge sheet did neither — so on a device with gesture
/// navigation its last row sat under the system bar. `showDragHandle` was set
/// on most but not all, which meant the affordance telling you a sheet can be
/// dragged away appeared on some sheets and not others, with no rule behind
/// which.
///
/// `isScrollControlled` is on for all of them. It does not force a tall sheet —
/// content that sizes itself still does — it only lifts the half-screen cap
/// that would otherwise clip a long list instead of scrolling it.
///
/// [dismissible] is the one real axis of difference: the recording sheet must
/// not be swiped away mid-recording, and a sheet that cannot be dragged away
/// must not advertise a drag handle.
///
/// **The bottom `SafeArea` is not redundant with `useSafeArea`.** Flutter
/// applies `SafeArea(bottom: false)` for that flag — it guards the status bar
/// and nothing else, and its own documentation says so: "the bottom sheet
/// extends all the way to the bottom of the screen, including any system
/// intrusions." Every sheet has to inset its own bottom edge, and the ones
/// that remembered to did it three different ways. On a phone using gesture
/// navigation the intrusion is small enough to look like padding; switch the
/// same phone to three-button navigation and the sheet's last control — Delete
/// on a note, Save on a picker — sits under the navigation bar.
Future<T?> nexShowSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
  bool swipeToClose = false,
  NexSheetOrigin? from,
}) => showModalBottomSheet<T>(
  context: context,
  // Opening out of a card takes a little longer than sliding up: the eye
  // has further to follow.
  sheetAnimationStyle: from == null
      ? null
      : const AnimationStyle(
          duration: Duration(milliseconds: 380),
          reverseDuration: Duration(milliseconds: 220),
        ),
  // This shared wrapper supplies the glass material itself. An opaque modal
  // sheet behind it would leave the backdrop filter nothing to sample.
  // The route keeps this colour for its lifetime. If it starts transparent
  // in glass mode and the preference changes while it is open, the content
  // must supply the newly opaque surface itself.
  backgroundColor: Colors.transparent,
  // The sheet's own material clips to wherever its route has slid it, which
  // would cut the opening off at that edge; the glass surface inside rounds
  // the corners itself.
  clipBehavior: from == null ? null : Clip.none,
  barrierColor: context.nexVisualStyle.liquidGlass
      ? Colors.black.withValues(alpha: 0.24)
      : null,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: dismissible,
  enableDrag: dismissible,
  showDragHandle: false,
  builder: (context) {
    final handle = Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    final guarded = !dismissible && swipeToClose;
    final sheet = NexGlassSurface(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(NexRadius.xl),
      ),
      fallbackColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dismissible) handle,
          if (guarded) _SwipeHandle(child: handle),
          Flexible(child: SafeArea(top: false, child: builder(context))),
        ],
      ),
    );
    final framed = guarded ? _SwipeToClose(child: sheet) : sheet;
    return from == null ? framed : NexCardOpening(origin: from, child: framed);
  },
);

/// Swipe-down for a sheet whose editor guards unsaved work — from its handle,
/// from anywhere that does not scroll, or by pulling its content past the
/// top.
///
/// Those sheets turn Flutter's own drag dismissal off, because it pops the
/// route directly and walks straight past the editor's "discard changes?"
/// question. That left them closable only by Cancel — a sheet you cannot
/// swipe away reads as stuck. This drag ends in [Navigator.maybePop]
/// instead, which is exactly the path the system back gesture takes, so the
/// editor's PopScope still decides: a clean editor closes, a dirty one asks.
class _SwipeToClose extends StatefulWidget {
  const _SwipeToClose({required this.child});

  final Widget child;

  @override
  State<_SwipeToClose> createState() => _SwipeToCloseState();
}

class _SwipeToCloseState extends State<_SwipeToClose>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails details) {
    _offset.value = (_offset.value + details.delta.dy).clamp(0, 10000);
  }

  void _end(DragEndDetails details) {
    final height = context.size?.height ?? 400;
    final fling = (details.primaryVelocity ?? 0) > 700;
    final far = _offset.value > height * 0.25;
    // Back to rest either way: when the pop goes ahead the route's own exit
    // animation carries the sheet off, and when the editor asks first the
    // sheet is already where the question expects it.
    unawaited(
      _offset.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
    if (fling || far) unawaited(Navigator.of(context).maybePop());
  }

  /// Whether the current drag is pulling the sheet down past the top of its
  /// own scrolling content.
  bool _pulling = false;

  /// From anywhere on the sheet, not only its handle: a list already at its
  /// top that is pulled further down takes the sheet with it, the way a
  /// bottom sheet does everywhere else on the phone.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is OverscrollNotification &&
        n.dragDetails != null &&
        (n.overscroll < 0 || _pulling)) {
      _pulling = true;
      _offset.value = (_offset.value - n.overscroll).clamp(0, 10000);
    } else if (n is ScrollUpdateNotification &&
        _pulling &&
        n.dragDetails != null) {
      // Pushed back up while pulling: the sheet rises before the content
      // scrolls.
      _offset.value = (_offset.value - n.scrollDelta!).clamp(0, 10000);
      if (_offset.value == 0) _pulling = false;
    } else if (n is ScrollEndNotification && _pulling) {
      _pulling = false;
      _end(
        DragEndDetails(primaryVelocity: n.dragDetails?.primaryVelocity ?? 0),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => _SwipeScope(
    onUpdate: _drag,
    onEnd: _end,
    child: NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      // Parts of the sheet that do not scroll — its heading, the space
      // between fields — drag it directly.
      child: GestureDetector(
        onVerticalDragUpdate: _drag,
        onVerticalDragEnd: _end,
        child: AnimatedBuilder(
          animation: _offset,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _offset.value),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

class _SwipeScope extends InheritedWidget {
  const _SwipeScope({
    required this.onUpdate,
    required this.onEnd,
    required super.child,
  });

  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

  @override
  bool updateShouldNotify(_SwipeScope old) => false;
}

/// The handle itself, with a touch target far larger than the bar it draws:
/// the full width of the sheet and 28 points tall.
class _SwipeHandle extends StatelessWidget {
  const _SwipeHandle({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_SwipeScope>()!;
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).closeButtonLabel,
      onTap: () => unawaited(Navigator.of(context).maybePop()),
      child: GestureDetector(
        key: const ValueKey('nex-sheet-swipe-handle'),
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: scope.onUpdate,
        onVerticalDragEnd: scope.onEnd,
        child: SizedBox(
          width: double.infinity,
          height: 28,
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    );
  }
}

/// A bottom sheet body that always fills the sheet's width.
///
/// `showModalBottomSheet` does not push its content above the keyboard on
/// its own — every sheet with a text field has to add the keyboard's own
/// inset to its bottom padding by hand, or the field's last controls end up
/// hidden behind it the moment the field autofocuses. Doing that here once
/// means every [NexSheetBody] gets it for free.
class NexSheetBody extends StatelessWidget {
  const NexSheetBody({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final base = (padding ?? const EdgeInsets.all(NexSpacing.lg)).resolve(
      Directionality.of(context),
    );
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding:
            base +
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: child,
      ),
    );
  }
}
