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
        (rune >= 0x0370 &&
            rune <= 0x058F &&
            !(rune >= 0x0590 && rune <= 0x05FF))) {
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

class _DirectionalLine extends StatelessWidget {
  const _DirectionalLine(this.text, this.style);

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final direction = nexDirectionOf(text);
    return Text(
      text.isEmpty ? '\u200B' : text,
      style: style,
      textDirection: direction,
      textAlign: direction == TextDirection.rtl
          ? TextAlign.right
          : direction == TextDirection.ltr
          ? TextAlign.left
          : TextAlign.start,
    );
  }
}

/// A block of the user's own writing, laid out in the direction it is written.
///
/// Only the paragraph turns. Wrapping a whole card or sheet in a
/// [Directionality] also moves its icons, dates and buttons, so a Persian note
/// came out mirrored against everything around it — the text was right and the
/// layout was wrong. Direction belongs to the text; the surface keeps the
/// direction the interface language gives it.
class NexBodyText extends StatelessWidget {
  const NexBodyText(this.text, {super.key, this.style, this.maxLines});

  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    if (maxLines == null && text.contains('\n')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in text.split('\n')) _DirectionalLine(line, style),
        ],
      );
    }
    final direction = nexDirectionOf(text);
    return SizedBox(
      // Full width, so a short right-to-left line reaches the right edge rather
      // than hugging the left one it happens to start at.
      width: double.infinity,
      child: Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        textDirection: direction,
        textAlign: direction == TextDirection.rtl
            ? TextAlign.right
            : TextAlign.start,
      ),
    );
  }
}

/// Rebuilds a text field as the script being typed into it changes.
///
/// A `TextField` takes its direction from the ambient [Directionality] — the
/// interface language — unless it is told otherwise, and the interface
/// language is not what decides here. A Persian sentence typed into a
/// left-to-right field is laid out around the wrong base direction, so it
/// scrambles as it is written and settles the moment it is saved.
///
/// The rebuild has to happen per keystroke, which is why this listens to the
/// controller rather than taking a string: the direction is a property of
/// text that does not exist yet.
///
/// ```dart
/// NexAutoDirection(
///   controller: controller,
///   builder: (context, direction) => TextField(
///     controller: controller,
///     textDirection: direction,
///     textAlign: TextAlign.start,
///   ),
/// )
/// ```
///
/// A null direction means the text carries none of its own — it is empty, or
/// it is a number — and the field should keep the ambient one. That is what
/// puts a placeholder at the right edge in Persian and the left in English.
class NexAutoDirection extends StatelessWidget {
  const NexAutoDirection({
    super.key,
    required this.controller,
    required this.builder,
  });

  final TextEditingController controller;
  final Widget Function(BuildContext context, TextDirection? direction) builder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) =>
            builder(context, nexDirectionOf(value.text)),
      );
}
