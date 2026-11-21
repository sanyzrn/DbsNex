import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../tokens/nex_contrast.dart';
import 'nex_selection_menu.dart';

part 'nex_code_web.dart';

/// Code in the one shape source is read in: fixed-width, left to right, and
/// coloured by what each part of it is.
///
/// The direction is imposed here for the same reason a fenced block in
/// [NexMarkdown] imposes it: source is written left to right, and a Persian
/// comment must not turn the indentation of every line around it. The
/// interface language has no vote.
///
/// [highlight] is false for timeline previews. A card shows two lines of a
/// note and is built on every scroll; tokenizing the whole of a long snippet
/// to draw the first two lines would make the timeline pay for code nobody is
/// reading. [maxLines] bounds it further, and [selectable] is off there for
/// the same reason a card is one tap target rather than a text field.
///
/// [spans] is for a caller that has already coloured the whole of a longer
/// source and is drawing it a piece at a time — see [nexSliceCodeSpans]. Given
/// them, this widget paints exactly those spans and does no tokenizing of its
/// own, so a chunk boundary cannot change how a comment or a string is read.
class NexCodeText extends StatefulWidget {
  const NexCodeText(
    this.code, {
    super.key,
    this.language = NexCodeLanguage.plainText,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.selectable = false,
    this.highlight = true,
    this.softWrap = false,
    this.spans,
  });

  final String code;
  final NexCodeLanguage language;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final bool selectable;
  final bool highlight;
  final bool softWrap;

  /// Pre-coloured pieces covering exactly [code], from [nexHighlightCode] or
  /// [nexSliceCodeSpans]. Null colours [code] here instead.
  final List<TextSpan>? spans;

  static TextStyle monospaceStyle(TextStyle? style) =>
      (style ?? const TextStyle()).copyWith(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Courier New', 'monospace'],
      );

  @override
  State<NexCodeText> createState() => _NexCodeTextState();
}

class _NexCodeTextState extends State<NexCodeText> {
  (String, NexCodeLanguage, ColorScheme)? _highlightKey;
  List<TextSpan>? _spans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = NexCodeText.monospaceStyle(
      widget.style ?? theme.textTheme.bodyLarge,
    );
    var spans = widget.spans;
    if (spans == null &&
        widget.highlight &&
        widget.language != NexCodeLanguage.plainText) {
      final key = (widget.code, widget.language, theme.colorScheme);
      if (_highlightKey != key) {
        _highlightKey = key;
        _spans = nexHighlightCode(
          widget.code,
          widget.language,
          style: base,
          scheme: theme.colorScheme,
        );
      }
      spans = _spans;
    }
    final text = TextSpan(
      style: base,
      text: spans == null ? widget.code : null,
      children: spans,
    );
    final body = widget.selectable
        ? SelectableText.rich(
            text,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
            maxLines: widget.maxLines,
            contextMenuBuilder: nexReadingMenu,
            style: base,
          )
        : Text.rich(
            text,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
            softWrap: widget.softWrap,
          );
    return Directionality(textDirection: TextDirection.ltr, child: body);
  }
}

/// The part of [spans] that covers `start`–`end` of the source they were made
/// for, keeping every piece's style.
///
/// A long snippet is drawn one bounded chunk at a time, but its syntax is a
/// property of the whole source: a block comment, a triple-quoted string or a
/// template literal that runs past the chunk boundary must not turn back into
/// punctuation on the next widget. Colouring the whole source once and taking
/// each chunk's share of those spans gives every chunk the same reading, and
/// costs one pass instead of one pass per chunk.
///
/// Offsets outside [spans]' own text are clamped, so a stale chunk can never
/// throw. The result always joins back into `code.substring(start, end)`.
///
/// The spans' cumulative ends are indexed once per list and reused, so drawing
/// the nth chunk of a long file does not walk every span of it again: what a
/// viewport shows is sliced in a fraction of a frame instead of once per span
/// per chunk.
List<TextSpan> nexSliceCodeSpans(List<TextSpan> spans, int start, int end) {
  if (spans.isEmpty) return const <TextSpan>[];
  final ends = _spanEndsOf(spans);
  final total = ends.last;
  final from = start < 0 ? 0 : (start > total ? total : start);
  final to = end < from ? from : (end > total ? total : end);
  if (to <= from) return const <TextSpan>[];

  // The first span whose end passes `from` holds it.
  var low = 0;
  var high = ends.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (ends[mid] <= from) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  final pieces = <TextSpan>[];
  for (var i = low; i < spans.length; i++) {
    final offset = i == 0 ? 0 : ends[i - 1];
    if (offset >= to) break;
    final text = spans[i].text ?? '';
    final take = from > offset ? from - offset : 0;
    final stop = to < ends[i] ? to - offset : text.length;
    if (stop > take) {
      final span = spans[i];
      pieces.add(
        take == 0 && stop == text.length
            ? span
            : TextSpan(text: text.substring(take, stop), style: span.style),
      );
    }
  }
  return pieces;
}

/// Cumulative ends, one per span, remembered for the list's lifetime.
///
/// The lists come from [nexHighlightCode], which never mutates one after
/// returning it; an expanded list keyed by identity is collected with it.
final _spanEnds = Expando<List<int>>();

List<int> _spanEndsOf(List<TextSpan> spans) {
  final known = _spanEnds[spans];
  if (known != null) return known;
  final ends = List<int>.filled(spans.length, 0);
  var offset = 0;
  for (var i = 0; i < spans.length; i++) {
    offset += spans[i].text?.length ?? 0;
    ends[i] = offset;
  }
  _spanEnds[spans] = ends;
  return ends;
}

/// The coloured pieces of [code], for the surfaces that draw it themselves.
///
/// The spans join back into [code] exactly — every character is in exactly
/// one of them — so selecting or copying what is drawn cannot invent or lose
/// a space. A language this build does not know is returned as one plain
/// span rather than guessed at.
List<TextSpan> nexHighlightCode(
  String code,
  NexCodeLanguage language, {
  required TextStyle style,
  required ColorScheme scheme,
}) {
  if (language == NexCodeLanguage.plainText || code.isEmpty) {
    return <TextSpan>[TextSpan(text: code)];
  }
  final ground = scheme.surfaceContainerHighest.withValues(alpha: 1);
  final comment = TextStyle(
    color: nexReadableOn(scheme.onSurfaceVariant, ground),
    fontStyle: FontStyle.italic,
  );
  final keyword = TextStyle(
    color: nexReadableOn(scheme.primary, ground),
    fontWeight: FontWeight.w600,
  );
  final string = TextStyle(color: nexReadableOn(scheme.tertiary, ground));
  final number = TextStyle(color: nexReadableOn(scheme.secondary, ground));
  final type = TextStyle(color: nexReadableOn(scheme.primary, ground));
  final punctuation = TextStyle(
    color: nexReadableOn(scheme.onSurfaceVariant, ground),
  );

  final spans = <TextSpan>[];
  if (language == NexCodeLanguage.html || language == NexCodeLanguage.css) {
    final html = language == NexCodeLanguage.html;
    final scan = html ? _scanHtml : _scanCss;
    final markup = html ? _htmlStyles(scheme, ground) : null;
    var cursor = 0;
    scan(code, (start, end, kind) {
      if (cursor < start) {
        spans.add(TextSpan(text: code.substring(cursor, start)));
      }
      spans.add(
        TextSpan(
          text: code.substring(start, end),
          style:
              markup?[kind] ??
              switch (kind) {
                _WebToken.comment => comment,
                _WebToken.keyword => keyword,
                _WebToken.name => number,
                _WebToken.string || _WebToken.bareValue => string,
                _WebToken.number => number,
                _WebToken.punctuation => punctuation,
              },
        ),
      );
      cursor = end;
    });
    if (cursor < code.length) {
      spans.add(TextSpan(text: code.substring(cursor)));
    }
    return spans;
  }

  final spec = _specFor(language)!;
  final php = language == NexCodeLanguage.php;
  final plain = StringBuffer();
  void flush() {
    if (plain.isEmpty) return;
    spans.add(TextSpan(text: plain.toString()));
    plain.clear();
  }

  void token(String text, TextStyle? tokenStyle) {
    flush();
    spans.add(TextSpan(text: text, style: tokenStyle));
  }

  final length = code.length;
  var i = 0;
  while (i < length) {
    final unit = code.codeUnitAt(i);
    final c = code[i];
    if (php && (c == '<' || c == '?')) {
      final tag = _phpTag.matchAsPrefix(code, i);
      if (tag != null) {
        token(tag[0]!, keyword);
        i = tag.end;
        continue;
      }
      if (_phpHeredocEnd(code, i) case final int end) {
        token(code.substring(i, end), string);
        i = end;
        continue;
      }
    }
    if (spec.slashComments &&
        c == '/' &&
        i + 1 < length &&
        code.codeUnitAt(i + 1) == 0x2F) {
      final end = _lineEnd(code, i);
      token(code.substring(i, end), comment);
      i = end;
      continue;
    }
    if (spec.blockComments &&
        c == '/' &&
        i + 1 < length &&
        code.codeUnitAt(i + 1) == 0x2A) {
      final close = code.indexOf('*/', i + 2);
      final end = close < 0 ? length : close + 2;
      token(code.substring(i, end), comment);
      i = end;
      continue;
    }
    if (spec.hashComments && c == '#' && !(php && code.startsWith('#[', i))) {
      final end = _lineEnd(code, i);
      token(code.substring(i, end), comment);
      i = end;
      continue;
    }
    final prefixQuote = spec.prefixes ? _prefixQuote(code, i, spec) : null;
    if (prefixQuote != null) {
      final end = _stringEnd(code, prefixQuote, spec);
      token(code.substring(i, end), string);
      i = end;
      continue;
    }
    if (c == "'" || c == '"' || (spec.templateStrings && c == '`')) {
      final end = _stringEnd(code, i, spec);
      token(code.substring(i, end), string);
      i = end;
      continue;
    }
    if (_isDigit(unit) ||
        (c == '.' && i + 1 < length && _isDigit(code.codeUnitAt(i + 1)))) {
      final match = _number.matchAsPrefix(code, i);
      if (match != null) {
        token(match[0]!, number);
        i = match.end;
        continue;
      }
    }
    final identifier = (php ? _phpIdentifier : _identifier).matchAsPrefix(
      code,
      i,
    );
    if (identifier != null) {
      final word = identifier[0]!;
      final name = php ? word.toLowerCase() : word;
      final tokenStyle = spec.keywords.contains(name)
          ? keyword
          : (php && word.startsWith(r'$')) || spec.types.contains(name)
          ? type
          : null;
      if (tokenStyle == null) {
        plain.write(word);
      } else {
        token(word, tokenStyle);
      }
      i = identifier.end;
      continue;
    }
    if (_isSpace(unit)) {
      plain.write(c);
      i++;
      continue;
    }
    // Punctuation is drawn in one piece until something that can start a
    // token. One span per bracket would be thousands of them in a long file
    // for no difference on screen.
    final start = i;
    i++;
    while (i < length &&
        !_isSpace(code.codeUnitAt(i)) &&
        !_couldStart(code, i, spec, php: php)) {
      i++;
    }
    token(code.substring(start, i), punctuation);
  }
  flush();
  return spans;
}

final class _LanguageSpec {
  const _LanguageSpec({
    this.keywords = const <String>{},
    this.types = const <String>{},
    this.slashComments = false,
    this.hashComments = false,
    this.blockComments = false,
    this.tripleQuotes = false,
    this.multilineStrings = false,
    this.templateStrings = false,
    this.prefixes = false,
  });

  final Set<String> keywords;
  final Set<String> types;
  final bool slashComments;
  final bool hashComments;
  final bool blockComments;
  final bool tripleQuotes;
  final bool multilineStrings;
  final bool templateStrings;
  final bool prefixes;
}

const _dartKeywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

const _dartTypes = <String>{
  'bool',
  'double',
  'Duration',
  'Future',
  'int',
  'Iterable',
  'List',
  'Map',
  'num',
  'Object',
  'Set',
  'Stream',
  'String',
};

const _javascriptKeywords = <String>{
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'debugger',
  'default',
  'delete',
  'do',
  'else',
  'export',
  'extends',
  'false',
  'finally',
  'for',
  'from',
  'function',
  'get',
  'if',
  'import',
  'in',
  'instanceof',
  'let',
  'new',
  'null',
  'of',
  'return',
  'set',
  'static',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'typeof',
  'undefined',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

const _javascriptTypes = <String>{
  'Array',
  'Boolean',
  'Date',
  'Error',
  'JSON',
  'Map',
  'Math',
  'Number',
  'Object',
  'Promise',
  'RegExp',
  'Set',
  'String',
  'Symbol',
};

const _pythonKeywords = <String>{
  'and',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'class',
  'continue',
  'def',
  'del',
  'elif',
  'else',
  'except',
  'False',
  'finally',
  'for',
  'from',
  'global',
  'if',
  'import',
  'in',
  'is',
  'lambda',
  'None',
  'nonlocal',
  'not',
  'or',
  'pass',
  'raise',
  'return',
  'True',
  'try',
  'while',
  'with',
  'yield',
};

const _pythonTypes = <String>{
  'bool',
  'bytes',
  'dict',
  'float',
  'int',
  'list',
  'object',
  'set',
  'str',
  'tuple',
};

const _jsonKeywords = <String>{'false', 'null', 'true'};

_LanguageSpec? _specFor(NexCodeLanguage language) => switch (language) {
  NexCodeLanguage.plainText ||
  NexCodeLanguage.html ||
  NexCodeLanguage.css => null,
  NexCodeLanguage.dart => const _LanguageSpec(
    keywords: _dartKeywords,
    types: _dartTypes,
    slashComments: true,
    blockComments: true,
    tripleQuotes: true,
    prefixes: true,
  ),
  NexCodeLanguage.javascript => const _LanguageSpec(
    keywords: _javascriptKeywords,
    types: _javascriptTypes,
    slashComments: true,
    blockComments: true,
    templateStrings: true,
  ),
  NexCodeLanguage.python => const _LanguageSpec(
    keywords: _pythonKeywords,
    types: _pythonTypes,
    hashComments: true,
    tripleQuotes: true,
    prefixes: true,
  ),
  NexCodeLanguage.json => const _LanguageSpec(keywords: _jsonKeywords),
  NexCodeLanguage.php => _phpSpec,
};

/// Where a string's prefix — Dart's `r`, Python's `f`/`b`/`rb` — ends and its
/// quote begins, or null when this is not a prefixed string.
int? _prefixQuote(String code, int start, _LanguageSpec spec) {
  if (!spec.prefixes ||
      (start > 0 && _isIdentifierUnit(code.codeUnitAt(start - 1)))) {
    return null;
  }
  var i = start;
  while (i < code.length && i - start < 2) {
    final unit = code.codeUnitAt(i);
    if (!_isPrefixLetter(unit)) break;
    i++;
  }
  if (i == start || i >= code.length) return null;
  final quote = code.codeUnitAt(i);
  return quote == 0x22 || quote == 0x27 ? i : null;
}

bool _isPrefixLetter(int unit) =>
    unit == 0x72 || // r
    unit == 0x52 || // R
    unit == 0x62 || // b
    unit == 0x42 || // B
    unit == 0x75 || // u
    unit == 0x55 || // U
    unit == 0x66 || // f
    unit == 0x46; // F

/// The end of the string starting at [quote], including the closing quotes.
///
/// A string that is not closed before its line ends stops there rather than
/// colouring the rest of the file: one missing quote is a typo, not an
/// instruction to swallow every line after it.
int _stringEnd(String code, int quote, _LanguageSpec spec) {
  final marker = code[quote];
  final triple =
      spec.tripleQuotes &&
      quote + 2 < code.length &&
      code[quote + 1] == marker &&
      code[quote + 2] == marker;
  final close = triple ? '$marker$marker$marker' : marker;
  var i = quote + close.length;
  while (i < code.length) {
    final unit = code.codeUnitAt(i);
    if (unit == 0x5C) {
      i += 2;
      continue;
    }
    if (code.startsWith(close, i)) return i + close.length;
    if (!triple && !spec.multilineStrings && (unit == 0x0A || unit == 0x0D)) {
      return i;
    }
    i++;
  }
  return code.length;
}

int _lineEnd(String code, int start) {
  final end = code.indexOf('\n', start);
  return end < 0 ? code.length : end;
}

bool _couldStart(String code, int i, _LanguageSpec spec, {required bool php}) {
  final unit = code.codeUnitAt(i);
  if (_isSpace(unit)) return true;
  final c = code[i];
  if (php && (c == '<' || c == '?')) return true;
  if (c == "'" || c == '"' || (spec.templateStrings && c == '`')) return true;
  if (spec.slashComments &&
      c == '/' &&
      i + 1 < code.length &&
      code.codeUnitAt(i + 1) == 0x2F) {
    return true;
  }
  if (spec.blockComments &&
      c == '/' &&
      i + 1 < code.length &&
      code.codeUnitAt(i + 1) == 0x2A) {
    return true;
  }
  if (spec.hashComments && c == '#') return true;
  if (_isDigit(unit) ||
      (c == '.' && i + 1 < code.length && _isDigit(code.codeUnitAt(i + 1)))) {
    return true;
  }
  if (spec.prefixes && _prefixQuote(code, i, spec) != null) return true;
  return _isIdentifierStart(unit) || (php && unit >= 0x80);
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

bool _isIdentifierStart(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x5F ||
    unit == 0x24;

bool _isIdentifierUnit(int unit) => _isIdentifierStart(unit) || _isDigit(unit);

final _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');
final _number = RegExp(
  r'0[xX][0-9a-fA-F_]+|0[bB][01_]+|(?:\d[\d_]*)(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?|\.\d[\d_]*(?:[eE][+-]?\d+)?',
);
