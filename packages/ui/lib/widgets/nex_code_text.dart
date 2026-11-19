import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../tokens/nex_contrast.dart';
import 'nex_selection_menu.dart';

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
class NexCodeText extends StatelessWidget {
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
  });

  final String code;
  final NexCodeLanguage language;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final bool selectable;
  final bool highlight;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = (style ?? theme.textTheme.bodyLarge ?? const TextStyle())
        .copyWith(
          // By family name rather than a bundled font, for the same reason
          // the Markdown renderer does it: the app ships one typeface for its
          // own text, and the platform's mono is the right wrong font for
          // source.
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Courier New', 'monospace'],
        );
    final spans = highlight && language != NexCodeLanguage.plainText
        ? nexHighlightCode(
            code,
            language,
            style: base,
            scheme: theme.colorScheme,
          )
        : <TextSpan>[TextSpan(text: code)];
    final text = TextSpan(style: base, children: spans);
    final body = selectable
        ? SelectableText.rich(
            text,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
            maxLines: maxLines,
            contextMenuBuilder: nexReadingMenu,
            style: base,
          )
        : Text.rich(
            text,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
            maxLines: maxLines,
            overflow: overflow,
            softWrap: softWrap,
          );
    return Directionality(textDirection: TextDirection.ltr, child: body);
  }
}

/// The coloured pieces of [code], for the surfaces that draw it themselves.
///
/// The spans join back into [code] exactly — every character is in exactly
/// one of them — so selecting or copying what is drawn cannot invent or lose
/// a space. A language this build does not know is returned as one plain
/// span rather than guessed at.
@visibleForTesting
List<TextSpan> nexHighlightCode(
  String code,
  NexCodeLanguage language, {
  required TextStyle style,
  required ColorScheme scheme,
}) {
  final spec = _specFor(language);
  if (spec == null || code.isEmpty) {
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
    if (spec.hashComments && c == '#') {
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
    final identifier = _identifier.matchAsPrefix(code, i);
    if (identifier != null) {
      final word = identifier[0]!;
      final tokenStyle = spec.keywords.contains(word)
          ? keyword
          : spec.types.contains(word)
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
        !_couldStart(code, i, spec)) {
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
    this.templateStrings = false,
    this.prefixes = false,
  });

  final Set<String> keywords;
  final Set<String> types;
  final bool slashComments;
  final bool hashComments;
  final bool blockComments;
  final bool tripleQuotes;
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
  NexCodeLanguage.plainText => null,
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
    if (!triple && (unit == 0x0A || unit == 0x0D)) return i;
    i++;
  }
  return code.length;
}

int _lineEnd(String code, int start) {
  final end = code.indexOf('\n', start);
  return end < 0 ? code.length : end;
}

bool _couldStart(String code, int i, _LanguageSpec spec) {
  final unit = code.codeUnitAt(i);
  if (_isSpace(unit)) return true;
  final c = code[i];
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
  return _isIdentifierStart(unit);
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
