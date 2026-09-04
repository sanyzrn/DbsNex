import 'package:flutter/widgets.dart';

/// The direction a piece of user text should be laid out in.
///
/// The app's own direction follows the *interface* language, so a Persian note
/// captured while the UI is in English used to render left-aligned even though
/// its glyphs shaped correctly — the text was right in itself and wrong on the
/// page. Direction here is a property of the content, not of the locale.
///
/// **The first strong character decides, and nothing after it.** This used to
/// ask `Bidi.detectRtlDirectionality`, which counts: it answers "right to
/// left" once enough of the string is right-to-left, on a ratio. That is a
/// reasonable guess about a finished sentence and the wrong question entirely
/// about one being typed, because the answer changes underneath the writer.
/// Start a note in English, add Persian, and at some unannounced keystroke the
/// whole box — English included — swung to the right. The same note then
/// landed on the timeline aligned one way or the other depending on how much
/// of each language it happened to contain.
///
/// First-strong is the rule Unicode itself specifies for this (UAX #9, P2/P3)
/// and what `dir="auto"` does on the web. Its virtue here is not accuracy so
/// much as *stability*: once the first letter is down the answer is fixed, so
/// nothing moves while you write.
///
/// Returns null when the text carries no strong directional character (a photo
/// note, a number, an empty body), leaving the ambient direction in place.
TextDirection? nexDirectionOf(String? text) {
  final value = text;
  if (value == null || value.isEmpty) return null;
  for (final rune in value.runes) {
    final direction = _directionOfRune(rune);
    if (direction != null) return direction;
  }
  return null;
}

/// The direction one character carries, or null if it carries none.
///
/// Neutral characters — digits, punctuation, spaces, emoji — deliberately
/// answer null rather than "left to right": "12:30" is not an English string,
/// and forcing it would misplace it inside a right-to-left card.
TextDirection? _directionOfRune(int rune) {
  // Arabic-Indic and Persian digits, and the number signs that go with them.
  //
  // They live inside the Arabic block, so the range below swept them up as
  // strong right-to-left — which contradicted the paragraph above this
  // function ("a number… leaves the ambient direction in place") and UAX #9
  // itself: P2 looks only at *strong* characters, and Unicode gives these
  // bidi class AN or EN. `"۱۲۳ abc"` is a left-to-right string that answered
  // rtl purely because its first character was a Persian digit, and a phone
  // number or a price at the start of a note flipped the whole paragraph in
  // the English UI. In the Persian one the ambient was already rtl, which is
  // why this went unnoticed.
  //
  // Only the numbers. The combining marks in this block are not strong
  // either, but none of them can legitimately begin a string, so excluding
  // them would be range arithmetic with no case behind it.
  if ((rune >= 0x0660 && rune <= 0x0669) || // Arabic-Indic digits ٠-٩
      (rune >= 0x06F0 && rune <= 0x06F9) || // Persian digits ۰-۹
      (rune >= 0x0600 && rune <= 0x0605) || // Arabic number signs
      (rune >= 0x066A && rune <= 0x066C) || // percent, decimal, thousands
      rune == 0x06DD) {
    return null;
  }
  // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic and the Arabic
  // presentation forms.
  if ((rune >= 0x0590 && rune <= 0x08FF) ||
      (rune >= 0xFB1D && rune <= 0xFDFF) ||
      (rune >= 0xFE70 && rune <= 0xFEFF)) {
    return TextDirection.rtl;
  }
  // Latin, then Latin supplements and IPA, then Greek/Cyrillic/Armenian.
  if ((rune >= 0x0041 && rune <= 0x005A) ||
      (rune >= 0x0061 && rune <= 0x007A) ||
      (rune >= 0x00C0 && rune <= 0x02AF) ||
      (rune >= 0x0370 && rune <= 0x058F)) {
    return TextDirection.ltr;
  }
  // Devanagari through Greek Extended, then CJK and Hangul.
  if ((rune >= 0x0900 && rune <= 0x1FFF) ||
      (rune >= 0x2E80 && rune <= 0xD7FF)) {
    return TextDirection.ltr;
  }
  return null;
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
