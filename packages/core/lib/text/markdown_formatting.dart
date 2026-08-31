/// Applying and removing the formatting a person can put on their own writing.
///
/// Nex stores a note's body as plain text and always has. That is not a
/// limitation being worked around here, it is the design: search, sync, merge,
/// export and every AI payload read `content` as-is, and a formatting model
/// held in a side table of offsets — which is how a chat app does it — would
/// have to be taught to every one of them. Markdown in the text costs none of
/// that, and a note exported as `.md` is then the same document anywhere else.
///
/// The markers are CommonMark's, not Telegram's, even though Telegram's
/// formatting menu is the shape being copied: `**bold**` and `~~strike~~`,
/// where Telegram writes `*bold*` and `~strike~`. Files and exports are the
/// tie-breaker — a note that leaves this app has to be right in the reader it
/// lands in, and that reader is a CommonMark one.
///
/// Everything here is a pure function from (text, selection) to (text,
/// selection). No controller, no widget, no context: the editing surfaces are
/// three different `TextField`s in two packages, and the interesting part —
/// what happens at the edges of a selection — is exactly the part worth
/// testing without pumping a frame.
library;

/// The inline formats the selection menu offers.
///
/// Underline and spoiler are deliberately absent. CommonMark has no syntax for
/// either, so both would have meant inventing one; underline would then be
/// `<u>` HTML in a plain-text note, and a spoiler in a private notebook hides
/// text from the one person allowed to read it.
enum NexInlineFormat {
  bold('**'),
  italic('_'),
  mono('`'),
  strikethrough('~~');

  const NexInlineFormat(this.marker);

  /// What is written on both sides of the selection.
  ///
  /// Italic is `_` rather than `*` so that bold-inside-italic does not
  /// produce a run of three asterisks whose meaning depends on which parser
  /// reads it.
  final String marker;
}

/// A body of text and where the selection sits in it afterwards.
///
/// The selection is half the answer. A toggle that returns only the new text
/// leaves the caller to guess where the cursor went, and the guess is wrong
/// every time the marker length differs from what was replaced — which is
/// always.
class NexFormattedText {
  const NexFormattedText(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is NexFormattedText &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(text, start, end);

  @override
  String toString() => 'NexFormattedText(${_quote(text)}, $start, $end)';

  static String _quote(String value) => "'${value.replaceAll('\n', r'\n')}'";
}

abstract final class NexTextFormatting {
  /// Wraps the selection in [format]'s markers, or unwraps it if it is already
  /// wrapped.
  ///
  /// Whitespace at the edges of the selection is left outside the markers.
  /// This is not tidiness: `** bold **` is not bold in any CommonMark parser,
  /// it is two asterisks, a word and two more asterisks — and a drag that
  /// overshoots a word by one space is the ordinary way to select one.
  static NexFormattedText toggleInline(
    String text,
    int start,
    int end,
    NexInlineFormat format,
  ) {
    final range = _Range.of(text, start, end);
    if (range.isEmpty) return NexFormattedText(text, range.start, range.end);

    final marker = format.marker;
    final selected = text.substring(range.start, range.end);

    // Already wrapped, with the markers inside the selection.
    if (selected.length > marker.length * 2 &&
        selected.startsWith(marker) &&
        selected.endsWith(marker)) {
      final bare = selected.substring(
        marker.length,
        selected.length - marker.length,
      );
      return NexFormattedText(
        text.replaceRange(range.start, range.end, bare),
        range.start,
        range.start + bare.length,
      );
    }

    // Already wrapped, with the markers just outside it — which is what the
    // selection looks like immediately after this method put them there.
    final before = range.start - marker.length;
    final after = range.end + marker.length;
    if (before >= 0 &&
        after <= text.length &&
        text.substring(before, range.start) == marker &&
        text.substring(range.end, after) == marker) {
      return NexFormattedText(
        text.replaceRange(before, after, selected),
        before,
        before + selected.length,
      );
    }

    return NexFormattedText(
      text.replaceRange(range.start, range.end, '$marker$selected$marker'),
      range.start + marker.length,
      range.end + marker.length,
    );
  }

  /// Turns the selection into a link to [url].
  ///
  /// The selection ends up on the whole link rather than on its label: the
  /// next thing anyone does after making a link by mistake is undo it, and a
  /// selection that covers the label alone makes that a three-step edit.
  static NexFormattedText link(String text, int start, int end, String url) {
    final range = _Range.of(text, start, end);
    final trimmed = url.trim();
    if (range.isEmpty || trimmed.isEmpty) {
      return NexFormattedText(text, range.start, range.end);
    }
    final label = text.substring(range.start, range.end);
    final replacement = '[$label]($trimmed)';
    return NexFormattedText(
      text.replaceRange(range.start, range.end, replacement),
      range.start,
      range.start + replacement.length,
    );
  }

  /// Marks every line the selection touches as a quote, or unmarks them if
  /// they all already are.
  ///
  /// Line-based, not selection-based: `>` is a block marker, and quoting half
  /// of a line produces a line with a `>` in the middle of it and no quote at
  /// all. Selecting one word and asking for a quote quotes that word's line,
  /// which is what every editor does and what anyone asking for it means.
  static NexFormattedText toggleQuote(String text, int start, int end) {
    final range = _Range.of(text, start, end, allowEmpty: true);
    final blockStart = _lineStart(text, range.start);
    final blockEnd = _lineEnd(text, range.end);
    final block = text.substring(blockStart, blockEnd);
    final lines = block.split('\n');

    final quoted = RegExp(r'^\s{0,3}>\s?');
    final content = lines.where((line) => line.trim().isNotEmpty);
    final allQuoted =
        content.isNotEmpty && content.every(quoted.hasMatch);

    final rewritten = [
      for (final line in lines)
        if (allQuoted)
          line.replaceFirst(quoted, '')
        // A blank line inside a quoted block ends the quote in CommonMark, so
        // it is marked too — otherwise asking for one quote produces two.
        else
          '> $line',
    ].join('\n');

    final out = text.replaceRange(blockStart, blockEnd, rewritten);
    return NexFormattedText(out, blockStart, blockStart + rewritten.length);
  }

  /// Removes the formatting this app writes, across the selection.
  ///
  /// Deliberately not a general Markdown stripper: it undoes what the menu
  /// above it can do, so that "Regular" is the exact inverse of the other
  /// buttons and nothing else. A heading someone typed by hand survives, and
  /// should — nobody asked for it to be removed.
  static NexFormattedText clear(String text, int start, int end) {
    final range = _Range.of(text, start, end);
    if (range.isEmpty) return NexFormattedText(text, range.start, range.end);
    final plain = NexMarkdownText.plain(
      text.substring(range.start, range.end),
      headings: false,
    );
    return NexFormattedText(
      text.replaceRange(range.start, range.end, plain),
      range.start,
      range.start + plain.length,
    );
  }

  static int _lineStart(String text, int index) {
    if (index <= 0) return 0;
    return text.lastIndexOf('\n', index - 1) + 1;
  }

  static int _lineEnd(String text, int index) {
    final next = text.indexOf('\n', index);
    return next == -1 ? text.length : next;
  }
}

/// Markdown with its markers taken off.
///
/// Needed the moment a note's body can contain them: a timeline card is a
/// picture of a note, not the note, and a search snippet is an excerpt. Both
/// show a line or two of raw `content`, and both would otherwise show the
/// asterisks — which is precisely the thing rendering was meant to stop.
abstract final class NexMarkdownText {
  /// [source] with the formatting markers removed and the words kept.
  ///
  /// Only paired markers are touched. A lone `*` in prose is an asterisk
  /// somebody typed, and an `_` inside `note_import.dart` is part of a
  /// filename; both survive, because a stripper that ate them would corrupt
  /// text that was never formatted in the first place.
  static String plain(String source, {bool headings = true}) {
    var out = source;
    // A link becomes its label. Done first: the URL inside one is full of
    // characters the marker passes below would otherwise chew on.
    out = out.replaceAllMapped(
      RegExp(r'\[([^\]\n]*)\]\([^)\s]*\)'),
      (match) => match[1] ?? '',
    );
    // Longest markers first, so `**bold**` is not read as two `*` pairs.
    for (final marker in const ['**', '~~', '`', '_', '*']) {
      out = _unwrap(out, marker);
    }
    out = out.replaceAllMapped(
      RegExp(r'(^|\n)\s{0,3}>\s?'),
      (match) => match[1] ?? '',
    );
    if (headings) {
      out = out.replaceAllMapped(
        RegExp(r'(^|\n)\s{0,3}#{1,6}\s+'),
        (match) => match[1] ?? '',
      );
    }
    return out;
  }

  /// [source] as it should read where a note is *shown* rather than rendered —
  /// a timeline card, a search hit, a notification.
  ///
  /// Gated on the same predicate the renderer uses, and deliberately so: the
  /// card is a picture of the note, and a card that strips markers the sheet
  /// would have kept (or keeps ones the sheet would have eaten) is a picture
  /// of a different note. It also keeps the stripper away from text that was
  /// never formatted — `2 * 3 * 4` is arithmetic, and unwrapping it would
  /// quietly delete two operators.
  static String preview(String source) =>
      nexLooksLikeMarkdown(source) ? plain(source) : source;

  static String _unwrap(String source, String marker) {
    final escaped = RegExp.escape(marker);
    // CommonMark's own intraword rule for `_`, and the reason it exists: an
    // underscore between two word characters is not emphasis, it is part of
    // `flutter_test_config`. Without this the stripper would quietly damage
    // text nobody ever formatted.
    final pattern = marker == '_'
        ? RegExp(r'(?<![\w\u0600-\u06FF])_([^\n_]+?)_(?![\w\u0600-\u06FF])')
        : RegExp('$escaped([^\\n]+?)$escaped');
    return source.replaceAllMapped(pattern, (match) => match[1] ?? '');
  }
}

/// A selection, in bounds and the right way round, with the whitespace at its
/// edges left out of it.
class _Range {
  const _Range(this.start, this.end);

  static _Range of(String text, int start, int end, {bool allowEmpty = false}) {
    var low = start < end ? start : end;
    var high = start < end ? end : start;
    if (low < 0) low = 0;
    if (high > text.length) high = text.length;
    if (low > high) low = high;
    if (allowEmpty) return _Range(low, high);
    while (low < high && _isSpace(text.codeUnitAt(low))) {
      low++;
    }
    while (high > low && _isSpace(text.codeUnitAt(high - 1))) {
      high--;
    }
    return _Range(low, high);
  }

  final int start;
  final int end;

  bool get isEmpty => start >= end;

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;
}

/// Whether [text] is worth rendering as Markdown rather than showing plain.
///
/// Three callers, one question. The assistant's replies are Markdown only when
/// the model chose to write Markdown; a note is Markdown only where its author
/// reached for the formatting menu; and a card must strip the markers exactly
/// where the sheet renders them, or the two disagree about what a note says.
///
/// Rendering an ordinary sentence through a Markdown parser is not wrong so
/// much as pointless, and it has one real cost: a lone `*` or `_` in prose —
/// or in Persian, a line that opens with `-` as a dash — would be eaten as
/// markup. So the renderer is used only where there is a structure to gain.
///
/// Deliberately conservative. It looks for constructs that are unambiguous at
/// the start of a line (a heading, a fence, a list marker, a quote, a rule, a
/// table row) or paired inline (`**bold**`, `` `code` ``), and ignores
/// everything else.
bool nexLooksLikeMarkdown(String text) {
  if (text.trim().isEmpty) return false;
  if (text.contains('```')) return true;
  if (RegExp(r'(^|\n)\s{0,3}#{1,6}\s+\S').hasMatch(text)) return true;
  if (RegExp(r'(^|\n)\s{0,3}([-*+]|\d{1,9}[.)])\s+\S').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'(^|\n)\s{0,3}>\s+\S').hasMatch(text)) return true;
  if (RegExp(r'(^|\n)\s{0,3}(([-*_])\s*){3,}\s*(\n|$)').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'(^|\n)\s*\|.+\|\s*(\n|$)').hasMatch(text)) return true;
  if (RegExp(r'\*\*[^*\n]+\*\*').hasMatch(text)) return true;
  if (RegExp(r'`[^`\n]+`').hasMatch(text)) return true;
  if (RegExp(r'\[[^\]\n]+\]\([^)\s]+\)').hasMatch(text)) return true;
  return false;
}
