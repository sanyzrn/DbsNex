part of 'nex_code_text.dart';

enum _WebToken {
  comment,
  keyword,
  name,
  string,
  bareValue,
  number,
  punctuation,
}

/// The default Notepad++ HTML hues, balanced for the active code surface.
Map<_WebToken, TextStyle> _htmlStyles(ColorScheme scheme, Color ground) {
  final dark = scheme.brightness == Brightness.dark;
  Color readable(int light, int darkValue) =>
      nexReadableOn(Color(dark ? darkValue : light), ground);
  return {
    _WebToken.keyword: TextStyle(
      color: readable(0xff1538b6, 0xff91aaff),
      fontWeight: FontWeight.w600,
    ),
    _WebToken.name: TextStyle(color: readable(0xffad272d, 0xffff9398)),
    _WebToken.string: TextStyle(color: readable(0xff6e25a5, 0xffd9a3ff)),
    _WebToken.bareValue: TextStyle(color: readable(0xff9a4a00, 0xffffbd78)),
    _WebToken.comment: TextStyle(
      color: readable(0xff287034, 0xff8bce90),
      fontStyle: FontStyle.italic,
    ),
    _WebToken.number: TextStyle(color: nexReadableOn(scheme.onSurface, ground)),
  };
}

typedef _WebHighlight = void Function(int start, int end, _WebToken token);

final _htmlTagStart = RegExp(
  r'<!doctype(?=[\s>]|$)|</?([a-z][\w:.-]*)(?=[\s/>]|$)',
  caseSensitive: false,
);
final _htmlTextBoundary = RegExp(r'[<&]');
final _htmlAttribute = RegExp(r'''[^\s=<>/"']+''');
final _htmlBareValue = RegExp(r'[^\s>]+');
final _htmlEntity = RegExp(r'&(?:#[xX][\da-fA-F]+|#\d+|[A-Za-z]\w*);');
final _htmlRawEnd = {
  for (final tag in ['script', 'style', 'textarea', 'title'])
    tag: RegExp(
      '</$tag'
      r'(?=[\s/>]|$)',
      caseSensitive: false,
    ),
};

void _scanHtml(String source, _WebHighlight emit) {
  var cursor = 0;
  while (cursor < source.length) {
    final start = source.indexOf(_htmlTextBoundary, cursor);
    if (start < 0) return;
    cursor = start + 1;
    if (source.startsWith('<!--', start)) {
      final close = source.indexOf('-->', start + 4);
      cursor = close < 0 ? source.length : close + 3;
      emit(start, cursor, _WebToken.comment);
      continue;
    }
    if (source.startsWith('<![CDATA[', start)) {
      final close = source.indexOf(']]>', start + 9);
      cursor = close < 0 ? source.length : close + 3;
      emit(start, cursor, _WebToken.string);
      continue;
    }
    final entity = _htmlEntity.matchAsPrefix(source, start);
    if (entity != null) {
      cursor = entity.end;
      emit(start, cursor, _WebToken.number);
      continue;
    }
    final tag = _htmlTagStart.matchAsPrefix(source, start);
    if (tag == null) continue;
    emit(start, tag.end, _WebToken.keyword);
    cursor = _scanHtmlTag(source, tag.end, emit);

    // In HTML-only highlighting, raw script and style content keeps its text
    // style. A tag-like string there is part of the embedded language.
    final close = _htmlRawEnd[tag[1]?.toLowerCase()];
    if (close != null &&
        !source.startsWith('</', start) &&
        (cursor < 2 || source.substring(cursor - 2, cursor) != '/>')) {
      final end = source.indexOf(close, cursor);
      if (end < 0) return;
      cursor = end;
    }
  }
}

int _scanHtmlTag(String source, int start, _WebHighlight emit) {
  var at = start;
  var expectingValue = false;
  while (at < source.length) {
    final unit = source.codeUnitAt(at);
    if (_isSpace(unit) || unit == 0x0C) {
      at++;
      continue;
    }
    if (unit == 0x3E || source.startsWith('/>', at)) {
      final end = at + (unit == 0x3E ? 1 : 2);
      emit(at, end, _WebToken.keyword);
      return end;
    }
    if (unit == 0x3C && !expectingValue) return at;
    if (unit == 0x22 || unit == 0x27) {
      final close = source.indexOf(source[at], at + 1);
      final end = close < 0 ? source.length : close + 1;
      emit(at, end, _WebToken.string);
      expectingValue = false;
      at = end;
      continue;
    }
    if (!expectingValue && unit == 0x3D) {
      emit(at, at + 1, _WebToken.punctuation);
      expectingValue = true;
      at++;
      continue;
    }
    final word = (expectingValue ? _htmlBareValue : _htmlAttribute)
        .matchAsPrefix(source, at);
    if (word == null) {
      at++;
      continue;
    }
    emit(at, word.end, expectingValue ? _WebToken.bareValue : _WebToken.name);
    expectingValue = false;
    at = word.end;
  }
  return at;
}

const _cssIdentifier = r'-?(?:[A-Za-z_\u0080-\uFFFF\\-])[\w\u0080-\uFFFF\\-]*';
final _cssWord = RegExp(_cssIdentifier);
final _cssSelector = RegExp(r'(?:[.#]|::?)' + _cssIdentifier);
final _cssDirective = RegExp(
  '@$_cssIdentifier'
  r'|!important\b',
  caseSensitive: false,
);
final _cssNumber = RegExp(
  r'[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?(?:[A-Za-z]+|%)?',
);
final _cssHex = RegExp(
  r'#(?:[a-fA-F\d]{8}|[a-fA-F\d]{6}|[a-fA-F\d]{4}|[a-fA-F\d]{3})(?![\w-])',
);
final _cssColon = RegExp(r'\s*:(?!:)');
final _cssRuleAhead = RegExp(
  r"""(?:[^;"'{}\\\r\n]|\\.|"(?:[^"\\\r\n]|\\.)*"|'(?:[^'\\\r\n]|\\.)*')*\{""",
);
const _cssPunctuation = '{}:;(),[]=*>~+';

void _scanCss(String source, _WebHighlight emit) {
  var inValue = false;
  var parentheses = 0;
  var brackets = 0;
  var i = 0;
  while (i < source.length) {
    final start = i;
    final char = source[i++];
    if (_isSpace(char.codeUnitAt(0))) continue;
    if (source.startsWith('/*', start)) {
      final close = source.indexOf('*/', i + 1);
      i = close < 0 ? source.length : close + 2;
      emit(start, i, _WebToken.comment);
      continue;
    }
    if (char == '"' || char == "'") {
      i = _stringEnd(source, start, const _LanguageSpec());
      emit(start, i, _WebToken.string);
      continue;
    }
    final control = parentheses == 0 && brackets == 0;
    if (control && (char == '{' || char == '}' || char == ';')) {
      inValue = false;
      emit(start, i, _WebToken.punctuation);
      continue;
    }
    final directive = _cssDirective.matchAsPrefix(source, start);
    if (directive != null) {
      i = directive.end;
      emit(start, i, _WebToken.keyword);
      continue;
    }
    final number = (inValue && char == '#' ? _cssHex : _cssNumber)
        .matchAsPrefix(source, start);
    if (number != null) {
      i = number.end;
      emit(start, i, _WebToken.number);
      continue;
    }
    if (!inValue) {
      final selector = _cssSelector.matchAsPrefix(source, start);
      if (selector != null) {
        i = selector.end;
        emit(start, i, _WebToken.keyword);
        continue;
      }
    }
    final word = _cssWord.matchAsPrefix(source, start);
    if (word != null) {
      i = word.end;
      final colon = control && !inValue
          ? _cssColon.matchAsPrefix(source, i)
          : null;
      if (colon != null &&
          (word[0]!.startsWith('--') ||
              _cssRuleAhead.matchAsPrefix(source, colon.end) == null)) {
        inValue = true;
        emit(start, i, _WebToken.name);
      } else if (!inValue || source.startsWith('(', i)) {
        emit(start, i, _WebToken.keyword);
      }
      continue;
    }
    switch (char) {
      case '(':
        parentheses++;
      case ')' when parentheses > 0:
        parentheses--;
      case '[':
        brackets++;
      case ']' when brackets > 0:
        brackets--;
    }
    if (_cssPunctuation.contains(char)) {
      emit(start, i, _WebToken.punctuation);
    }
  }
}

final _phpTag = RegExp(r'<\?php(?=\s|$)|<\?=|\?>', caseSensitive: false);
final _phpIdentifier = RegExp(r'\$?[A-Za-z_\u0080-\uFFFF][\w\u0080-\uFFFF]*');
final _phpHeredoc = RegExp(
  r"""<<<[ \t]*(?:'([a-zA-Z_]\w*)'|"([a-zA-Z_]\w*)"|([a-zA-Z_]\w*))[ \t]*\r?\n""",
);

int? _phpHeredocEnd(String source, int at) {
  final start = _phpHeredoc.matchAsPrefix(source, at);
  if (start == null) return null;
  final label = start[1] ?? start[2] ?? start[3]!;
  final close = RegExp(
    r'^[ \t]*' + RegExp.escape(label) + r'(?![\w\u0080-\uFFFF])',
    multiLine: true,
  );
  return close.allMatches(source, start.end).firstOrNull?.end ?? source.length;
}

const _phpSpec = _LanguageSpec(
  slashComments: true,
  hashComments: true,
  blockComments: true,
  templateStrings: true,
  multilineStrings: true,
  types: {
    'array',
    'bool',
    'callable',
    'float',
    'int',
    'iterable',
    'mixed',
    'never',
    'object',
    'parent',
    'self',
    'string',
    'void',
  },
  keywords: {
    '__class__',
    '__dir__',
    '__file__',
    '__function__',
    '__line__',
    '__method__',
    '__namespace__',
    '__trait__',
    'abstract',
    'and',
    'as',
    'break',
    'case',
    'catch',
    'class',
    'clone',
    'const',
    'continue',
    'declare',
    'default',
    'do',
    'echo',
    'else',
    'elseif',
    'empty',
    'enddeclare',
    'endfor',
    'endforeach',
    'endif',
    'endswitch',
    'endwhile',
    'enum',
    'eval',
    'exit',
    'extends',
    'false',
    'final',
    'finally',
    'fn',
    'for',
    'foreach',
    'function',
    'global',
    'goto',
    'if',
    'implements',
    'include',
    'include_once',
    'instanceof',
    'insteadof',
    'interface',
    'isset',
    'list',
    'match',
    'namespace',
    'new',
    'null',
    'or',
    'print',
    'private',
    'protected',
    'public',
    'readonly',
    'require',
    'require_once',
    'return',
    'static',
    'switch',
    'throw',
    'trait',
    'true',
    'try',
    'unset',
    'use',
    'var',
    'while',
    'xor',
    'yield',
  },
);
