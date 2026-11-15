import 'package:flutter/material.dart';

import 'nex_contrast.dart';
import 'nex_tokens.dart';

/// The soft wash of a note kind's own colour that a note sits on, in the list
/// and in the grid alike (2.7.0).
///
/// The colour gathers in the starting corner and thins out across the card,
/// the way light falls on paper, so a screen of notes reads as colour without
/// shouting it. Kept low on purpose: a hint of the kind, never a fill. While
/// several notes are being picked, a picked one takes a stronger wash.
///
/// [muted] and [outline] are the page's secondary tones walked against the
/// wash's own start: the page's muted grey can fall under 4.5:1 on a
/// coloured card, and a card's quiet words should stay as readable as they
/// were on the plain one.
typedef NexNoteWash = ({
  Color tint,
  Color from,
  Color to,
  Color muted,
  Color outline,
});

NexNoteWash nexNoteWash(
  String? wireName,
  ColorScheme scheme, {
  bool picked = false,
}) {
  // Remembered: every card and tile asks this on every build, and the two
  // readable tones are each a contrast search — on a scrolling grid of
  // tiles that was the same few answers worked out again for every tile
  // that came into view (2.7.2). The answer depends on nothing but the kind,
  // the colours it is read from and the picked state.
  final key = (
    wireName,
    picked,
    scheme.brightness,
    scheme.primary.toARGB32(),
    scheme.surfaceContainerLowest.toARGB32(),
    scheme.surfaceContainerHighest.toARGB32(),
    scheme.onSurfaceVariant.toARGB32(),
    scheme.outline.toARGB32(),
  );
  final cached = _washes[key];
  if (cached != null) return cached;
  if (_washes.length > 96) _washes.clear();
  return _washes[key] = _wash(wireName, scheme, picked);
}

final _washes = <Object, NexNoteWash>{};

NexNoteWash _wash(String? wireName, ColorScheme scheme, bool picked) {
  final dark = scheme.brightness == Brightness.dark;
  final tint = nexNoteTypeTint(wireName, scheme);
  Color wash(double alpha) => Color.alphaBlend(
    tint.withValues(alpha: alpha),
    scheme.surfaceContainerLowest,
  );
  final from = wash(picked ? 0.24 : (dark ? 0.09 : 0.07));
  return (
    tint: tint,
    from: from,
    to: wash(picked ? 0.16 : (dark ? 0.03 : 0.015)),
    muted: nexReadableOn(scheme.onSurfaceVariant, from),
    outline: nexReadableOn(scheme.outline, from),
  );
}
