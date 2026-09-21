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

import 'package:flutter/material.dart';

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
    child: child,
  );
}
