/// A code snippet kept as the Markdown note it already is.
///
/// A note has no field for "this is code": [Note.content] is the whole note,
/// and every text note is Markdown. So a snippet is stored the way Markdown
/// already stores one — a single fenced block whose info string names the
/// language — and read back by [NexCodeSnippet.parse]. The language and the
/// fence belong to the note; the code inside them is what the person typed,
/// copied and edited.
///
/// Nothing is trimmed anywhere in here. Indentation, tabs, blank lines and
/// trailing spaces are the code; a round trip that lost them would quietly
/// change what the snippet says.
library;

/// The languages a snippet can be written in, for now.
///
/// Deliberately small: a language is a highlighting rule set and a menu row,
/// and five of each is enough to start. [plainText] is the one that is never
/// highlighted and never guesses.
enum NexCodeLanguage {
  plainText('text'),
  dart('dart'),
  javascript('javascript'),
  python('python'),
  json('json');

  const NexCodeLanguage(this.id);

  /// What the fence's info string says. It is also what is shown to the
  /// reader for a language this build does not know.
  final String id;

  /// The languages with a highlighter, in the order the picker shows them.
  static const selectable = [plainText, dart, javascript, python, json];

  /// [id] as one of these, or null for a fence this build does not know.
  ///
  /// The aliases are the spellings other tools write into their fences —
  /// `js` and `py` are common enough that treating them as unknown would
  /// show a highlighted snippet as plain text.
  static NexCodeLanguage? fromId(String id) {
    final key = id.trim().toLowerCase();
    return switch (key) {
      'text' || 'plain' || 'plaintext' || 'txt' || '' => plainText,
      'dart' => dart,
      'js' || 'javascript' || 'jsx' || 'mjs' || 'cjs' => javascript,
      'py' || 'python' || 'python3' => python,
      'json' || 'jsonc' => json,
      _ => null,
    };
  }
}

/// A snippet read out of, or written into, a Markdown note.
final class NexCodeSnippet {
  const NexCodeSnippet({
    required this.code,
    this.language = NexCodeLanguage.plainText,
    this.rawLanguage,
  });

  /// The code exactly as it was typed: line endings, tabs, indentation,
  /// blank lines and trailing spaces included.
  final String code;

  /// The language to highlight with. A fence whose info string this build
  /// does not know reads as [NexCodeLanguage.plainText] and keeps its own
  /// info string in [rawLanguage], so editing the code does not rename it.
  final NexCodeLanguage language;

  /// The info string as stored, when it is not one of [language]'s own ids.
  final String? rawLanguage;

  /// What goes in the fence: the person's chosen language, or the one that
  /// was already there.
  String get languageId => rawLanguage ?? language.id;

  NexCodeSnippet withCode(String code) =>
      NexCodeSnippet(code: code, language: language, rawLanguage: rawLanguage);

  /// The same code in [language], replacing a stored info string this build
  /// did not know.
  NexCodeSnippet withLanguage(NexCodeLanguage language) =>
      NexCodeSnippet(code: code, language: language);

  /// The note this snippet is: one fenced block, in a fence long enough that
  /// no line of the code can close it early.
  String get markdown {
    final fence = '`' * _fenceLength(code);
    return '$fence$languageId\n$code\n$fence';
  }

  /// [source] as a snippet when the whole of it is one fenced block, or null.
  ///
  /// A note with prose in it — or a code fence among prose — is an ordinary
  /// Markdown note and stays one. This is the whole test: the first line is
  /// the fence, the last line closes it, and nothing sits outside them. That
  /// keeps every existing Markdown note reading as it did, while a note that
  /// was captured as code (or imported from a source file) becomes a snippet
  /// with a language and a copy button.
  static NexCodeSnippet? parse(String source) {
    final read = _read(source);
    if (read == null) return null;
    return NexCodeSnippet(
      code: read.code,
      language: read.language,
      rawLanguage: read.rawLanguage,
    );
  }

  /// The first [maxChars] of a snippet, for a timeline card or a search row.
  ///
  /// The timeline must not pay for the whole of a long snippet to draw two
  /// lines of it. Null for anything that is not a single fenced block, the
  /// same rule [parse] keeps.
  static NexCodeSnippet? previewOf(String source, {int maxChars = 640}) {
    final read = _read(source, maxChars: maxChars);
    if (read == null) return null;
    return NexCodeSnippet(
      code: read.code,
      language: read.language,
      rawLanguage: read.rawLanguage,
    );
  }

  static _Read? _read(String source, {int? maxChars}) {
    final openingEnd = source.indexOf('\n');
    if (openingEnd <= 0) return null;
    final opening = _opening.firstMatch(source.substring(0, openingEnd));
    if (opening == null) return null;
    final marker = opening.group(1)!;
    final info = opening.group(2)!.trim();
    // CommonMark: a backtick fence's info string may not contain a backtick.
    if (marker.startsWith('`') && info.contains('`')) return null;

    // The closing fence is the last line. One trailing newline — what an
    // editor may leave after the fence — is allowed; anything else after it
    // means this is a block inside a longer note, not a snippet.
    var end = source.length;
    if (source.codeUnitAt(end - 1) == 0x0A) end--;
    if (end <= openingEnd) return null;
    final closingStart = source.lastIndexOf('\n', end - 1) + 1;
    if (closingStart <= openingEnd) return null;
    final closing = _closing.firstMatch(source.substring(closingStart, end));
    if (closing == null) return null;
    final closingMarker = closing.group(1)!;
    if (closingMarker[0] != marker[0] || closingMarker.length < marker.length) {
      return null;
    }

    // [NexCodeSnippet.markdown] writes exactly one newline between the code
    // and the closing fence. Removing exactly that one is what keeps a code
    // that ends in blank lines, or in no newline at all, byte for byte.
    final codeStart = openingEnd + 1;
    final codeEnd = closingStart - 1;
    if (codeEnd < codeStart) return null;
    var previewEnd = codeEnd;
    if (maxChars != null && previewEnd - codeStart > maxChars) {
      previewEnd = codeStart + maxChars;
      // A cut between the halves of a surrogate pair would be a broken
      // character on the card.
      if (previewEnd > codeStart &&
          _isHighSurrogate(source.codeUnitAt(previewEnd - 1))) {
        previewEnd--;
      }
    }
    final code = source.substring(codeStart, previewEnd);
    final id = info.isEmpty ? '' : info.split(RegExp(r'\s+')).first;
    final known = NexCodeLanguage.fromId(id);
    return _Read(
      code: code,
      language: known ?? NexCodeLanguage.plainText,
      rawLanguage: known == null && id.isNotEmpty ? id : null,
    );
  }

  /// A fence longer than the longest run of backticks in [code], so a
  /// snippet about Markdown — fences included — cannot close its own block.
  static int _fenceLength(String code) {
    var longest = 0;
    var run = 0;
    for (final unit in code.codeUnits) {
      if (unit == 0x60) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
    }
    final needed = longest + 1;
    return needed < 3 ? 3 : needed;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  /// An opening fence: at most three spaces of indent, three or more of one
  /// marker, and the rest of the line as the info string.
  static final _opening = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');

  /// A closing fence: the same marker, whitespace after it and nothing else.
  /// Which marker, and how long, is checked against the opening fence.
  static final _closing = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*$');
}

final class _Read {
  const _Read({
    required this.code,
    required this.language,
    required this.rawLanguage,
  });

  final String code;
  final NexCodeLanguage language;
  final String? rawLanguage;
}
