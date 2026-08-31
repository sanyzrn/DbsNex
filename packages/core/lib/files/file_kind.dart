/// What a file note *is*, for the purpose of showing it rather than naming it.
///
/// A file note stores a filename and a path; until now the sheet that opened
/// one could do exactly two things with it — print the name and hand the path
/// to the operating system — with a single exception for Markdown, which was
/// read off disk and rendered. That exception was hard-coded as
/// `nexIsMarkdownFile`, and every other format that could be shown the same
/// way was invisible for want of one predicate.
///
/// This is that predicate, generalised: one place that answers "what shape is
/// this file", so the widgets above it can decide what to *do* about it. It
/// stays in `packages/core` because it is a question about a name, not about
/// a screen or a filesystem — pure logic, testable in the fast Dart-only CI
/// job, and reusable by anything that later needs the same answer (search
/// filters and the timeline card both plausibly do).
enum NexFileKind {
  /// Rendered as Markdown.
  markdown,

  /// Shown as itself, with the app's own body style and no interpretation. A
  /// `.txt` is not Markdown and must not be read as it: someone's shopping
  /// list that happens to start a line with `#` is not a heading.
  plainText,

  /// Source and configuration. Monospace, preserved whitespace, no wrapping.
  code,

  /// Delimiter-separated rows, shown as a table.
  table,

  image,
  audio,
  video,

  /// A document format with structure this app cannot read yet — PDF, DOCX,
  /// ODT and friends. Named, not shown; these are the later phases.
  document,

  /// Everything else. Named and handed to the OS, exactly as before.
  other;

  /// Whether this kind is read off disk as text.
  ///
  /// The three that are share a size limit, a decode step and a set of failure
  /// messages, so one widget serves all of them.
  bool get isText =>
      this == NexFileKind.markdown ||
      this == NexFileKind.plainText ||
      this == NexFileKind.code ||
      this == NexFileKind.table;
}

/// Decides a [NexFileKind] from a filename and, where one was supplied, a MIME
/// type.
abstract final class NexFileKinds {
  /// The kind of the file at [path].
  ///
  /// A *specific* MIME type wins: a sharing app that says `text/markdown`
  /// about a file called `notes` knows something the name does not. A generic
  /// one does not win, because it says nothing — Android's share sheet hands
  /// out `application/octet-stream` freely, and the extension is then the only
  /// thing that knows. Both halves of that rule were already written down in
  /// the Markdown predicate this replaces; only the second was implemented.
  static NexFileKind of({String? path, String? mimeType}) {
    final byMime = _fromMime(mimeType);
    if (byMime != null) return byMime;
    if (path == null || path.isEmpty) return NexFileKind.other;
    return _byExtension[extensionOf(path)] ?? NexFileKind.other;
  }

  /// The extension of [path], lowercased and without its dot.
  ///
  /// `''` when there is none, and for a dotfile — `.gitignore` has no
  /// extension, it has a name that starts with a dot, and treating `gitignore`
  /// as one would be a guess.
  static String extensionOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static NexFileKind? _fromMime(String? mimeType) {
    // `text/markdown; charset=utf-8` is one type with a parameter.
    final type = mimeType?.toLowerCase().split(';').first.trim();
    if (type == null || type.isEmpty) return null;
    if (_genericMimes.contains(type)) return null;
    if (const {'text/markdown', 'text/x-markdown'}.contains(type)) {
      return NexFileKind.markdown;
    }
    if (const {'text/csv', 'text/tab-separated-values'}.contains(type)) {
      return NexFileKind.table;
    }
    if (type == 'text/plain') return NexFileKind.plainText;
    // SVG is an image by MIME and text by nature, and this app can render
    // neither — no vector renderer, and showing the source of a drawing helps
    // nobody. It stays a named file.
    if (type == 'image/svg+xml') return NexFileKind.other;
    if (type.startsWith('image/')) return NexFileKind.image;
    if (type.startsWith('audio/')) return NexFileKind.audio;
    if (type.startsWith('video/')) return NexFileKind.video;
    if (const {
      'application/pdf',
      'application/msword',
      'application/rtf',
      'text/rtf',
      'application/epub+zip',
      'application/vnd.oasis.opendocument.text',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    }.contains(type)) {
      return NexFileKind.document;
    }
    // Every other `text/*` is source or markup of some sort — `text/html`,
    // `text/x-dart`, `text/xml`. Monospace is the honest rendering.
    if (type.startsWith('text/')) return NexFileKind.code;
    return null;
  }

  /// MIME types that carry no information. Falling through to the extension is
  /// strictly better than believing these.
  static const _genericMimes = {
    'application/octet-stream',
    'application/binary',
    'binary/octet-stream',
    'content/unknown',
    '*/*',
  };

  static const _byExtension = <String, NexFileKind>{
    // Markdown, in the spellings that exist in the wild.
    'md': NexFileKind.markdown,
    'markdown': NexFileKind.markdown,
    'mdown': NexFileKind.markdown,
    'mkd': NexFileKind.markdown,
    'mdtext': NexFileKind.markdown,

    'txt': NexFileKind.plainText,
    'text': NexFileKind.plainText,
    'log': NexFileKind.plainText,

    'csv': NexFileKind.table,
    'tsv': NexFileKind.table,

    // Source and configuration. Not an attempt at a complete list of
    // programming languages — the ones a person plausibly shares into a notes
    // app, plus the config formats everybody has a file of.
    'dart': NexFileKind.code,
    'py': NexFileKind.code,
    'js': NexFileKind.code,
    'mjs': NexFileKind.code,
    'cjs': NexFileKind.code,
    'ts': NexFileKind.code,
    'tsx': NexFileKind.code,
    'jsx': NexFileKind.code,
    'java': NexFileKind.code,
    'kt': NexFileKind.code,
    'kts': NexFileKind.code,
    'swift': NexFileKind.code,
    'c': NexFileKind.code,
    'h': NexFileKind.code,
    'cc': NexFileKind.code,
    'cpp': NexFileKind.code,
    'hpp': NexFileKind.code,
    'cs': NexFileKind.code,
    'go': NexFileKind.code,
    'rs': NexFileKind.code,
    'rb': NexFileKind.code,
    'php': NexFileKind.code,
    'lua': NexFileKind.code,
    'sh': NexFileKind.code,
    'bash': NexFileKind.code,
    'zsh': NexFileKind.code,
    'ps1': NexFileKind.code,
    'sql': NexFileKind.code,
    'html': NexFileKind.code,
    'htm': NexFileKind.code,
    'css': NexFileKind.code,
    'scss': NexFileKind.code,
    'xml': NexFileKind.code,
    'json': NexFileKind.code,
    'yaml': NexFileKind.code,
    'yml': NexFileKind.code,
    'toml': NexFileKind.code,
    'ini': NexFileKind.code,
    'cfg': NexFileKind.code,
    'conf': NexFileKind.code,
    'env': NexFileKind.code,
    'properties': NexFileKind.code,
    'gradle': NexFileKind.code,
    'patch': NexFileKind.code,
    'diff': NexFileKind.code,

    'jpg': NexFileKind.image,
    'jpeg': NexFileKind.image,
    'png': NexFileKind.image,
    'webp': NexFileKind.image,
    'gif': NexFileKind.image,
    'bmp': NexFileKind.image,
    'heic': NexFileKind.image,
    'heif': NexFileKind.image,

    // What the bundled player can actually decode. `.wma` is deliberately
    // absent: Android has never decoded it, and offering a play button that
    // fails is worse than offering none.
    'mp3': NexFileKind.audio,
    'm4a': NexFileKind.audio,
    'aac': NexFileKind.audio,
    'wav': NexFileKind.audio,
    'ogg': NexFileKind.audio,
    'oga': NexFileKind.audio,
    'opus': NexFileKind.audio,
    'flac': NexFileKind.audio,
    'amr': NexFileKind.audio,

    'mp4': NexFileKind.video,
    'm4v': NexFileKind.video,
    'mov': NexFileKind.video,
    'mkv': NexFileKind.video,
    'webm': NexFileKind.video,
    '3gp': NexFileKind.video,
    'avi': NexFileKind.video,

    'pdf': NexFileKind.document,
    'doc': NexFileKind.document,
    'docx': NexFileKind.document,
    'odt': NexFileKind.document,
    'rtf': NexFileKind.document,
    'epub': NexFileKind.document,
    'xls': NexFileKind.document,
    'xlsx': NexFileKind.document,
    'ppt': NexFileKind.document,
    'pptx': NexFileKind.document,
  };
}
