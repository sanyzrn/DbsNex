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
    // The focus node lives *inside* the editor: its render object is the text
    // itself, and scrolling that to the end leaves the field's own box — its
    // label, its counter, its border — below the keyboard. The field is the
    // unit to bring up, so the nearest TextField above the focus is the
    // target, and the focus is only the fallback (the native editor on
    // Android is not a TextField in the tree).
    BuildContext target = focused;
    focused.visitAncestorElements((element) {
      if (element.widget is TextField || element.widget is TextFormField) {
        target = element;
        return false;
      }
      return true;
    });
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
