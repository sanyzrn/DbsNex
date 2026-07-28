import 'package:flutter/widgets.dart';
// intl exports a TextDirection of its own, which is not dart:ui's — importing
// it unhidden makes every TextDirection in this file ambiguous.
import 'package:intl/intl.dart' hide TextDirection;

/// The direction a piece of user text should be laid out in.
///
/// The app's own direction follows the *interface* language, so a Persian note
/// captured while the UI is in English used to render left-aligned even though
/// its glyphs shaped correctly — the text was right in itself and wrong on the
/// page. Direction here is a property of the content, not of the locale.
///
/// Returns null when the text carries no strong directional character (a photo
/// note, a number, an empty body), leaving the ambient direction in place.
TextDirection? nexDirectionOf(String? text) {
  final value = text?.trim();
  if (value == null || value.isEmpty) return null;
  if (!_hasStrongDirection(value)) return null;
  return Bidi.detectRtlDirectionality(value)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

/// Whether the text contains any character that carries a direction at all.
///
/// `detectRtlDirectionality` answers false for neutral text, which is
/// indistinguishable from "definitely left-to-right" — and forcing LTR on
/// "12:30" inside a right-to-left card would misplace it.
bool _hasStrongDirection(String value) {
  for (final rune in value.runes) {
    // Latin, Greek, Cyrillic and friends.
    if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A) ||
        (rune >= 0x00C0 && rune <= 0x02AF) ||
        (rune >= 0x0370 && rune <= 0x058F && !(rune >= 0x0590 && rune <= 0x05FF))) {
      return true;
    }
    // Hebrew, Arabic, Persian, Syriac, Thaana and the Arabic presentation forms.
    if ((rune >= 0x0590 && rune <= 0x07BF) ||
        (rune >= 0x0860 && rune <= 0x08FF) ||
        (rune >= 0xFB1D && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF)) {
      return true;
    }
    // CJK, Hangul, Devanagari and other strongly left-to-right scripts.
    if (rune >= 0x0900 && rune <= 0x1FFF) return true;
    if (rune >= 0x2E80 && rune <= 0xD7FF) return true;
  }
  return false;
}

/// Lays [child] out in the direction [text] itself implies.
///
/// A no-op when the text has no direction of its own.
class NexTextDirection extends StatelessWidget {
  const NexTextDirection({super.key, required this.text, required this.child});

  final String? text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final direction = nexDirectionOf(text);
    if (direction == null) return child;
    return Directionality(textDirection: direction, child: child);
  }
}
