/// Puts the keyboard away when a tap lands on nothing that wanted it.
///
/// A phone keyboard covers half the screen and has no way out of its own. The
/// system back gesture closes it, but on most screens here that is also how
/// you leave the screen, so the two are one motion people do not want to
/// guess at. The rest of the app becomes the way out instead: tap anything
/// that is not a field and the keyboard goes.
///
/// It wraps everything and catches only what falls through, which is not a
/// trick — the gesture arena resolves a tap in favour of the deepest
/// recognizer that wants it, and this is the shallowest there is. A tap
/// inside a text field, on a button, on a card, on a checklist row is claimed
/// where it landed and never reaches here. What reaches here is the gaps: the
/// padding around a sheet, the blank half of a settings page, the space
/// beside a title. Those are exactly the taps that mean "not this".
///
/// Gated on the keyboard actually being up, read live from the view rather
/// than from a `MediaQuery` the build closed over — the keyboard opens and
/// shuts without this rebuilding. Without that gate every stray tap would
/// also drop focus off whatever held it, which changes real behaviour on a
/// desktop or with a hardware keyboard and buys nothing anywhere.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// See the library doc: one tap target under the whole app, for the taps
/// nothing else claimed.
class NexKeyboardDismisser extends StatelessWidget {
  const NexKeyboardDismisser({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    // So the empty regions count too: without this a tap on a part of the
    // screen no child paints would hit nothing at all and never arrive.
    behavior: HitTestBehavior.translucent,
    // Not a control. A tap target the size of the app is noise to anyone
    // reading the screen aloud.
    excludeFromSemantics: true,
    onTap: () {
      if (View.of(context).viewInsets.bottom <= 0) return;
      FocusManager.instance.primaryFocus?.unfocus();
    },
    child: _KeyboardGuard(view: View.of(context), child: child),
  );
}

/// A field where, while it is being typed in, a touch outside it only puts
/// the keyboard away (ADR-038).
///
/// Only the settings search is one. There the screen under the keyboard is a
/// list of switches and rows, and a touch meant to close the keyboard landed
/// on one of them. Everywhere else a touch outside the field does what it
/// touches, as in every other app: 1.91.0 made this rule app-wide, and a tag
/// picked or a Send pressed with the keyboard up stopped working.
///
/// While [focusNode] holds focus and the on-screen keyboard is up, the first
/// touch anywhere outside a text field — the rest of the sheet, the dimmed
/// screen above it — closes the keyboard and reaches nothing else: no tap,
/// drag or long press under it. The field, its clear button and its selection
/// handles work as always.
class NexGuardedField extends StatefulWidget {
  const NexGuardedField({
    super.key,
    required this.focusNode,
    required this.child,
  });

  final FocusNode focusNode;
  final Widget child;

  @override
  State<NexGuardedField> createState() => _NexGuardedFieldState();
}

class _NexGuardedFieldState extends State<NexGuardedField> {
  @override
  void initState() {
    super.initState();
    _guarded.add(widget.focusNode);
  }

  @override
  void didUpdateWidget(NexGuardedField old) {
    super.didUpdateWidget(old);
    if (old.focusNode == widget.focusNode) return;
    _guarded
      ..remove(old.focusNode)
      ..add(widget.focusNode);
  }

  @override
  void dispose() {
    _guarded.remove(widget.focusNode);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The focus nodes of every [NexGuardedField] on screen.
final _guarded = <FocusNode>{};

/// Under the whole app, so a guarded field's rule holds for the screen
/// around its sheet too. Stops the touch in hit testing: nothing below it is
/// hit at all, raw pointer listeners included.
class _KeyboardGuard extends SingleChildRenderObjectWidget {
  const _KeyboardGuard({required this.view, required Widget super.child});

  final FlutterView view;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderKeyboardGuard(view);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderKeyboardGuard).view = view;
  }
}

class _RenderKeyboardGuard extends RenderProxyBox {
  _RenderKeyboardGuard(this.view);

  FlutterView view;

  /// The keyboard is up and a guarded field holds focus.
  bool get _guarding {
    if (view.viewInsets.bottom <= 0) return false;
    return _guarded.any((node) => node.hasFocus);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (!_guarding) return super.hitTest(result, position: position);
    // Where the touch would go, found without handing it there yet.
    final probe = BoxHitTestResult();
    super.hitTest(probe, position: position);
    final onAField = probe.path.any(
      (entry) =>
          entry.target is RenderTapRegion &&
          (entry.target as RenderTapRegion).groupId == EditableText,
    );
    if (onAField) return super.hitTest(result, position: position);
    // Outside: this is all the touch reaches, start to finish.
    result.add(_StoppedTouch(this, position));
    return true;
  }

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    // Every touch in the app passes through here; only the one stopped
    // closes the keyboard. Acting on all of them was 1.91.0's other bug.
    if (entry is _StoppedTouch && event is PointerDownEvent) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }
}

class _StoppedTouch extends BoxHitTestEntry {
  _StoppedTouch(super.target, super.localPosition);
}
