/// A code snippet kept as the Markdown note it already is.
///
/// A note has no field for "this is code": `Note.content` is the whole note,
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

/// The supported snippet languages, in picker order.
enum NexCodeLanguage {
  plainText('text', 'Plain text', 'txt', 'Aa'),
  dart('dart', 'Dart', 'dart', 'Dart'),
  javascript('javascript', 'JavaScript', 'js', 'JS'),
  python('python', 'Python', 'py', 'Py'),
  json('json', 'JSON', 'json', '{ }'),
  html('html', 'HTML', 'html', '</>'),
  css('css', 'CSS', 'css', 'CSS'),
  php('php', 'PHP', 'php', 'PHP'),
  typescript('typescript', 'TypeScript', 'ts', 'TS'),
  kotlin('kotlin', 'Kotlin', 'kt', 'KT'),
  java('java', 'Java', 'java', 'Java'),
  swift('swift', 'Swift', 'swift', 'Swift'),
  c('c', 'C', 'c', 'C'),
  cpp('cpp', 'C++', 'cpp', 'C++'),
  csharp('csharp', 'C#', 'cs', 'C#'),
  go('go', 'Go', 'go', 'Go'),
  rust('rust', 'Rust', 'rs', 'RS'),
  sql('sql', 'SQL', 'sql', 'SQL'),
  bash('bash', 'Bash', 'sh', 'SH'),
  yaml('yaml', 'YAML', 'yaml', 'YML'),
  xml('xml', 'XML', 'xml', 'XML'),
  markdown('markdown', 'Markdown', 'md', 'MD');

  const NexCodeLanguage(this.id, this.label, this.extension, this.glyph);

  final String id;
  final String label;
  final String extension;
  final String glyph;

  static const selectable = values;

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
      'html' || 'htm' || 'html5' => html,
      'css' => css,
      'php' || 'php8' || 'phtml' => php,
      'ts' || 'tsx' || 'typescript' => typescript,
      'kt' || 'kts' || 'kotlin' => kotlin,
      'java' => java,
      'swift' => swift,
      'c' => c,
      'cpp' || 'c++' || 'cxx' || 'cc' || 'hpp' => cpp,
      'csharp' || 'cs' || 'c#' => csharp,
      'go' || 'golang' => go,
      'rust' || 'rs' => rust,
      'sql' || 'postgresql' || 'sqlite' => sql,
      'bash' || 'sh' || 'shell' || 'zsh' => bash,
      'yaml' || 'yml' => yaml,
      'xml' => xml,
      'markdown' || 'md' => markdown,
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
    this.storedInfo,
  });

  /// The whole info string the fence was read with — `js filename=app.js`,
  /// `python {.numberLines}` — kept while only the code changes and written
  /// back as it was (2.8.19): only its first word used to survive an edit.
  /// Choosing a language replaces it.
  final String? storedInfo;

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

  NexCodeSnippet withCode(String code) => NexCodeSnippet(
    code: code,
    language: language,
    rawLanguage: rawLanguage,
    storedInfo: storedInfo,
  );

  /// The same code in [language], replacing a stored info string this build
  /// did not know.
  NexCodeSnippet withLanguage(NexCodeLanguage language) =>
      NexCodeSnippet(code: code, language: language);

  /// The note this snippet is: one fenced block, in a fence long enough that
  /// no line of the code can close it early.
  String get markdown {
    final info = storedInfo ?? languageId;
    final marker = info.contains('`') ? '~' : '`';
    final fence = marker * _fenceLength(code, marker.codeUnitAt(0));
    return '$fence$info\n$code\n$fence';
  }

  /// [source] as a snippet when the whole of it is one fenced block, or null.
  ///
  /// A note with prose in it — or a code fence among prose — is an ordinary
  /// Markdown note and stays one. The first matching closing fence must
  /// also be the end of the note.
  static NexCodeSnippet? parse(String source) {
    final read = _read(source);
    if (read == null) return null;
    return NexCodeSnippet(
      code: read.code,
      language: read.language,
      rawLanguage: read.rawLanguage,
      storedInfo: read.info,
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
      storedInfo: read.info,
    );
  }

  static _Read? _read(String source, {int? maxChars}) {
    final opening = _opening.matchAsPrefix(source);
    if (opening == null) return null;
    final marker = opening.group(1)!;
    final openingEnd = source.indexOf('\n', opening.end);
    if (openingEnd < 0) return null;
    final crlf = source.codeUnitAt(openingEnd - 1) == 0x0D;
    final info = source
        .substring(opening.end, openingEnd - (crlf ? 1 : 0))
        .trim();
    final backtick = marker.startsWith('`');
    if (info.contains('\r') || backtick && info.contains('`')) return null;

    final codeStart = openingEnd + 1;
    final closer = backtick ? _backtickClose : _tildeClose;
    // Find marker runs with the string search so large snippets do not
    // run a regular expression over every line each time a card is built.
    var searchFrom = codeStart;
    while (true) {
      final run = source.indexOf(marker, searchFrom);
      if (run < 0) return null;
      searchFrom = run + marker.length;
      var lineStart = run;
      while (lineStart > codeStart &&
          run - lineStart < 3 &&
          source.codeUnitAt(lineStart - 1) == 0x20) {
        lineStart--;
      }
      if (source.codeUnitAt(lineStart - 1) != 0x0A) continue;
      final closing = closer.matchAsPrefix(source, lineStart);
      if (closing == null) continue;
      // A closing fence followed by more Markdown ends the first block,
      // even if a later line could also close the fence. Only blank lines
      // after it are allowed — a fence a file was pasted with a trailing
      // newline or two is still the same block.
      if (!_onlyBlank(source, closing.end)) return null;

      var codeEnd = closing.start;
      if (codeEnd > codeStart) {
        codeEnd--;
        if (crlf && source.codeUnitAt(codeEnd - 1) == 0x0D) codeEnd--;
      }
      return _readCode(source, info, codeStart, codeEnd, maxChars);
    }
  }

  static _Read _readCode(
    String source,
    String info,
    int codeStart,
    int codeEnd,
    int? maxChars,
  ) {
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
    final id = info.isEmpty ? '' : info.split(_whitespace).first;
    final known = NexCodeLanguage.fromId(id);
    return _Read(
      code: code,
      language: known ?? NexCodeLanguage.plainText,
      rawLanguage: known == null && id.isNotEmpty ? id : null,
      info: info.isEmpty ? null : info,
    );
  }

  /// A fence longer than any run of its marker inside the code.
  static int _fenceLength(String code, int marker) {
    var longest = 0;
    var run = 0;
    for (final unit in code.codeUnits) {
      if (unit == marker) {
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

  static final _opening = RegExp(r' {0,3}(`{3,}|~{3,})');
  static final _whitespace = RegExp(r'\s+');

  static final _backtickClose = RegExp(r' {0,3}`{3,}[ \t]*(?:\r?\n|$)');
  static final _tildeClose = RegExp(r' {0,3}~{3,}[ \t]*(?:\r?\n|$)');

  /// Nothing but spaces, tabs and line endings left in [source].
  static bool _onlyBlank(String source, int from) {
    for (var i = from; i < source.length; i++) {
      final unit = source.codeUnitAt(i);
      if (unit != 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) {
        return false;
      }
    }
    return true;
  }
}

final class _Read {
  const _Read({
    required this.code,
    required this.language,
    required this.rawLanguage,
    required this.info,
  });

  final String code;
  final NexCodeLanguage language;
  final String? rawLanguage;
  final String? info;
}
