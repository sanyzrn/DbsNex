import 'package:flutter/material.dart';

/// Keeps the field being typed in above the keyboard.
///
/// The bug this answers (2.9.0, step 4): in Prompt Studio — and in any form
/// whose field sat low on a scrolled page — tapping the field opened the
/// keyboard over it. The scaffold did make room, but only the *caret* was
/// scrolled into view: a six-line body field was half under the keyboard, and
/// on a small screen the visible half was the top of the field, not the line
/// being written.
///
/// The framework's own rule is "keep the caret visible", and it is right for
/// the ordinary case. What it cannot know is that Nex draws tall multi-line
/// fields: a box that is 200 px high with the caret at its top is "visible"
/// as far as Flutter is concerned, and still half-covered. So this widget adds
/// the missing half of the rule, once, for the whole app: **when the keyboard
/// is up, the focused field's box is brought above it.**
///
/// Installed once in `app.dart`, above the Navigator, so it covers pages,
/// dialogs and sheets without a single per-screen patch. It does nothing when
/// the keyboard is closed, so a focus change on a device with a hardware
/// keyboard moves nothing.
///
/// * `keepVisibleAtEnd` rather than a fixed alignment: the scroll is the
///   smallest one that shows the end of the field — where somebody typing
///   usually is — and a field that already fits does not move at all.
/// * A focus change while the keyboard is up (Next, Tab, tapping another
///   field) is the same event as the keyboard opening, and is handled by the
///   same path.
/// * "Remove animations" gets no animation, here as everywhere else.
class NexFocusReveal extends StatefulWidget {
  const NexFocusReveal({super.key, required this.child});

  final Widget child;

  @override
  State<NexFocusReveal> createState() => _NexFocusRevealState();
}

class _NexFocusRevealState extends State<NexFocusReveal>
    with WidgetsBindingObserver {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _schedule();

  void _onFocusChanged() => _schedule();

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // After the frame: the keyboard's inset has been applied to the layout,
    // and the new focus has a render object to scroll to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _reveal();
      // And once more on the following frame. The first pass can run while
      // the scaffold is still growing into its new height (or while the
      // field's own caret-scroll is in flight), which leaves the box a little
      // lower than it could be — and the second pass has the settled layout
      // to correct it. Two frames, no timer, and nothing at all when the
      // keyboard is closed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal();
      });
    });
  }

  void _reveal() {
    final view = View.maybeOf(context);
    if (view == null || view.viewInsets.bottom <= 0) return;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null || !focused.mounted) return;
    final target = nexKeyboardRevealTarget(focused);
    if (!target.mounted) return;
    // Only something inside a scroll view has anywhere to scroll to.
    if (Scrollable.maybeOf(target) == null) return;
    // Instant, not animated: this runs while the keyboard itself is still
    // moving, and an animation racing that movement is what left the field
    // half-covered in the first attempt. The scroll is part of the keyboard
    // arriving, not a separate flourish.
    Scrollable.ensureVisible(
      target,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      duration: Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The box to bring above the keyboard for [focused]: the field's own frame.
///
/// The focus node belongs to the *editor*, not to the field. Scrolling what it
/// points at leaves the field's frame — label, counter, border — below the
/// keyboard, which is the report this rule answers. The frame is an
/// `InputDecorator`, and which way it lies from the focus depends on the path:
///
/// * the Flutter editor's focus node sits **inside** the decorator (right
///   beside the text), so it is found by walking up;
/// * the Android editor's focus node is the `Focus` that **wraps** the
///   decorator — the native `EditText` lives inside the frame the decorator
///   draws — so walking up from it finds nothing and the decorator is one of
///   its own descendants;
/// * the platform view's own node, which takes focus on a real device, sits
///   inside the decorator again.
///
/// Both directions are tried, so every path lands on the same box. Only when
/// there is no decorator at all (a custom editor) does it fall back to the
/// focus itself.
@visibleForTesting
BuildContext nexKeyboardRevealTarget(BuildContext focused) {
  final element = focused as Element;
  return _firstDescendant<InputDecorator>(element) ??
      _nearestAncestor<InputDecorator>(element) ??
      focused;
}

Element? _nearestAncestor<T extends Widget>(Element element) {
  Element? found;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is T) {
      found = ancestor;
      return false;
    }
    return true;
  });
  return found;
}

Element? _firstDescendant<T extends Widget>(Element root) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget is T) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found;
}
