/// While the keyboard is up, a touch outside what is being typed only puts
/// the keyboard away (ADR-038).
///
/// A phone keyboard covers half the screen, and the person typing is looking
/// at the words, not at what sits around them. Reaching for the empty part of
/// the screen to close the keyboard used to land, as often as not, on
/// whatever was there: the clear button on a birthday while a name was being
/// typed, a row of the recurring form, a search result. So the first touch
/// outside does exactly one thing, the thing it was meant for: the keyboard
/// goes, and nothing under the finger hears about it — not its tap, not its
/// drag, not its long press. The next touch is an ordinary one.
///
/// What counts as inside, and works with one touch as always:
///
/// - the field being typed in, its clear button and the rest of its
///   decoration, and its selection handles and Cut/Copy/Paste menu;
/// - any other text field, so moving to the next field is one tap;
/// - the controls that act on what is being typed — Send, Save, the
///   formatting bar — which mark themselves with [NexTypingAction]. Having to
///   tap Send twice is not safety, it is a broken composer;
/// - when the field is in a dialog, the whole dialog: a dialog built around
///   a field is one small typing surface, its OK and Cancel included. A
///   touch beside it, on the dimmed screen, closes the keyboard first.
///
/// The first three are Flutter's own text-field tap group ([TextFieldTapRegion]),
/// which is how the framework itself tells its toolbar and handles apart
/// from the rest of the screen.
///
/// It stops the touch in hit testing, under the whole app, so it holds for
/// raw pointer listeners as much as for buttons: nothing below is hit at all.
/// Gated on the keyboard actually being up, read live from the view, and on
/// focus being in a text field — with a hardware keyboard, or on a desktop,
/// every click behaves as it always did.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'nex_text_field.dart';

/// See the library doc: one hit test under the whole app.
class NexKeyboardDismisser extends SingleChildRenderObjectWidget {
  const NexKeyboardDismisser({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderKeyboardDismisser(View.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderKeyboardDismisser).view = View.of(context);
  }
}

/// A control that acts on what is being typed — Send beside a composer, Save
/// on an editor, the formatting bar — and so, like the field itself, works
/// with one touch while the keyboard is up. See [NexKeyboardDismisser].
///
/// Only for those: a control that does something else (deletes, navigates,
/// opens another page) is outside, and the first touch on it puts the
/// keyboard away instead.
class NexTypingAction extends TextFieldTapRegion {
  const NexTypingAction({super.key, required super.child});
}

class _RenderKeyboardDismisser extends RenderProxyBox {
  _RenderKeyboardDismisser(this.view);

  FlutterView view;

  /// The context of the text field being typed in while the keyboard is
  /// up, or null.
  BuildContext? get _typing {
    if (view.viewInsets.bottom <= 0) return null;
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return null;
    final field =
        context.findAncestorStateOfType<EditableTextState>() != null ||
        context.findAncestorWidgetOfExactType<NexTextField>() != null;
    return field ? context : null;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final field = _typing;
    if (field == null) return super.hitTest(result, position: position);
    // Where the touch would go, found without handing it there yet.
    final probe = BoxHitTestResult();
    super.hitTest(probe, position: position);
    if (_inside(probe, field)) {
      return super.hitTest(result, position: position);
    }
    // Outside: this is all the touch reaches, start to finish.
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  static bool _inside(BoxHitTestResult probe, BuildContext field) {
    final dialog = _dialogAround(field);
    return probe.path.any(
      (entry) =>
          entry.target == dialog ||
          entry.target is RenderTapRegion &&
              (entry.target as RenderTapRegion).groupId == EditableText,
    );
  }

  /// The box of the dialog [field] is in, if it is in one. Only the box
  /// itself: a touch on the space around it never reaches it.
  static RenderObject? _dialogAround(BuildContext field) {
    RenderObject? box;
    field.visitAncestorElements((element) {
      if (element.widget is Dialog) {
        box = element.findRenderObject();
        return false;
      }
      return true;
    });
    return box;
  }

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }
}
