import 'package:flutter/material.dart';

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
  const _DirectionalLine(this.text, this.style, {this.clamp = false});

  final String text;
  final TextStyle? style;

  /// Whether this line is one of a fixed few — a preview rather than the
  /// whole note — in which case it takes one row and ends in an ellipsis
  /// rather than wrapping into its neighbours' space.
  final bool clamp;

  @override
  Widget build(BuildContext context) {
    final direction = nexDirectionOf(text);
    return Text(
      text.isEmpty ? '\u200B' : text,
      style: style,
      maxLines: clamp ? 1 : null,
      overflow: clamp ? TextOverflow.ellipsis : null,
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
  const NexBodyText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.selectable = false,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;

  /// Whether a finger can take hold of these words.
  ///
  /// A `Text` cannot be selected at all — not by long press, not by double
  /// tap, no handles, nothing. That is Flutter's design and not a bug, but it
  /// is invisible from the outside: on a phone, a paragraph that does not
  /// answer a long press does not read as "this app has not implemented
  /// selection here", it reads as "selection in this app is broken". Nex
  /// renders most of what a person *reads* through this widget, so most of
  /// what a person reads could not be copied out of.
  ///
  /// True wraps the block in a [SelectionArea], which is what brings the long
  /// press, the double tap, the handles, the magnifier and Copy. The area
  /// rather than a `SelectableText` on purpose: `SelectableText` handles
  /// every gesture itself and dispatches none of them onward, so a tappable
  /// link or `code` span inside the same paragraph would stop answering — the
  /// same reason [NexMarkdown] is given an area from outside rather than made
  /// selectable from within.
  ///
  /// Off by default, because a timeline card is not a reading surface: it
  /// lives inside a swipe recognizer and a tap that opens the note, and a
  /// long press that starts selecting a preview is a long press that did not
  /// open the thing it was on. Selection belongs where the text is being
  /// read.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final body = _body();
    return selectable ? SelectionArea(child: body) : body;
  }

  Widget _body() {
    if (text.contains('\n')) {
      // Per line, clamped or not. It used to be per line only when nothing
      // was clamping it, and that exception is the bug: one direction over a
      // block of several lines is the *first* line's direction imposed on all
      // of them, so a note that opens in English lays its Persian lines out
      // left to right and a note that opens in Persian pushes its English
      // ones to the right. Which one looks wrong depends on which language
      // the note happens to start in, which is why it only ever happened
      // "sometimes".
      //
      // A budget is spent in source lines here rather than in wrapped ones.
      // That is a real difference — a single long line used to be allowed to
      // wrap into the whole budget — and it is the right one for a preview:
      // the first three lines of somebody's note tell you more about it than
      // the first three rows of its first sentence.
      final lines = text.split('\n');
      final shown = maxLines == null ? lines : lines.take(maxLines!).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in shown)
            _DirectionalLine(line, style, clamp: maxLines != null),
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

/// Runs a text field in the direction of the script being typed into it.
///
/// A `TextField` takes its direction from the ambient [Directionality] — the
/// interface language — unless it is told otherwise, and the interface
/// language is not what decides here. A Persian sentence typed into a
/// left-to-right field is laid out around the wrong base direction, so it
/// scrambles as it is written and settles the moment it is saved.
///
/// **It supplies a [Directionality], not just a `textDirection` argument**,
/// and that distinction is the whole reason this is a widget rather than a
/// function call. Setting `textDirection:` on the field turns the *glyphs*
/// and leaves everything built around them resolving against the ambient
/// direction: the decoration's padding, the hint, and — the one that is
/// actually painful — the selection handles, the magnifier and the context
/// menu, which are built from the field's context. Persian text in an
/// English interface got a right-to-left paragraph with a left-to-right
/// selection overlay on top of it, so the handles came up on the wrong ends
/// and dragging one ran the selection the wrong way. Owning the direction
/// for the whole subtree is what makes those agree.
///
/// The builder still receives the direction, because the field should pass it
/// on as `textDirection:` too — with both set they cannot drift, and the
/// argument is what pins the paragraph when the ambient one is inherited from
/// somewhere this widget does not own.
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
/// it is a number — and the field keeps the ambient one. That is what puts a
/// placeholder at the right edge in Persian and the left in English.
///
/// Two things it is careful about, both learned the hard way:
///
/// - **It rebuilds on a change of direction, not on a change of value.** A
///   `TextEditingController` notifies its listeners when the *selection*
///   moves, not only when the text does — so a `ValueListenableBuilder` on one
///   rebuilds the field on every frame of a handle drag, and a selection being
///   dragged through a widget that is being rebuilt under it is a selection
///   that fights back. Nothing below depends on the value, only on the
///   direction, so that is what is watched.
/// - **The [Directionality] is always there**, carrying the ambient direction
///   when the text has none of its own. Inserting or removing a widget changes
///   the shape of the tree, and the element below it is rebuilt from scratch —
///   which, for a focused field, means losing focus and selection at the
///   moment the first letter is typed, exactly when the direction stops being
///   null.
class NexAutoDirection extends StatefulWidget {
  const NexAutoDirection({
    super.key,
    required this.controller,
    required this.builder,
  });

  final TextEditingController controller;
  final Widget Function(BuildContext context, TextDirection? direction) builder;

  @override
  State<NexAutoDirection> createState() => _NexAutoDirectionState();
}

class _NexAutoDirectionState extends State<NexAutoDirection> {
  TextDirection? _direction;

  @override
  void initState() {
    super.initState();
    _direction = nexDirectionOf(widget.controller.text);
    widget.controller.addListener(_reread);
  }

  @override
  void didUpdateWidget(NexAutoDirection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_reread);
    widget.controller.addListener(_reread);
    _direction = nexDirectionOf(widget.controller.text);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reread);
    super.dispose();
  }

  void _reread() {
    final next = nexDirectionOf(widget.controller.text);
    if (next == _direction) return;
    setState(() => _direction = next);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: _direction ?? Directionality.of(context),
    child: Builder(
      // A `Builder`, so the field is built *under* the `Directionality` above
      // and reads it — `context` here is the one this widget was built with,
      // which still carries the old direction.
      builder: (inner) => widget.builder(inner, _direction),
    ),
  );
}
