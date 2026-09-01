import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads a `.docx` and writes what it says as Markdown.
///
/// A `.docx` is a zip of XML, so this needs an archive and a parser — which is
/// why it lives in the app rather than in `packages/core` beside the other
/// readers. Core's whole documented job is to depend on almost nothing, and
/// `xml` is not in its closure; it is already in this app's, through the
/// plugins. The layering cost is real and the alternative was worse: a
/// hand-rolled scanner over somebody else's XML, in a package chosen for
/// purity, to avoid naming a parser that is already on disk.
///
/// Markdown rather than a widget tree of its own, deliberately. The app can
/// already render Markdown, in a style the rest of it agrees with — so a
/// document opened in a note looks like a note, and every improvement to that
/// renderer arrives here for free. What is lost is everything Word can express
/// and Markdown cannot: fonts, colours, columns, floating images. A note is
/// not a word processor and showing a document is not opening it — the file
/// itself is one tap away in whatever does open it.
///
/// What survives: headings, bold, italic, strikethrough, lists, quotes,
/// hyperlinks, tables and line breaks.
abstract final class NexDocx {
  /// The largest file this will open.
  ///
  /// Compressed, so it does not bound the length of the document — hence the
  /// separate character cap below. It bounds the memory the unzip takes.
  static const maxBytes = 4 * 1024 * 1024;

  /// Past this much text, the rest is left unread and the caller is told.
  ///
  /// Roughly a hundred pages. The byte cap alone cannot stand in for this:
  /// text compresses ten to one, so a small `.docx` can hold a book.
  static const maxCharacters = 200 * 1024;

  /// The document as Markdown, or null when [bytes] are not a `.docx` this can
  /// read.
  ///
  /// Null covers every kind of failure on purpose. The caller has exactly one
  /// thing to say either way — it could not be shown, here is the file — and
  /// distinguishing "not a zip" from "no `word/document.xml`" would be a
  /// distinction only this function can appreciate.
  static NexDocxText? read(List<int> bytes) {
    if (bytes.length > maxBytes) return null;
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    final source = _entry(archive, 'word/document.xml');
    if (source == null) return null;
    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } catch (_) {
      return null;
    }
    final body = document.rootElement.getElement('w:body');
    if (body == null) return null;

    final links = _relationships(_entry(archive, 'word/_rels/document.xml.rels'));
    final blocks = <_Block>[];
    var length = 0;
    var truncated = false;
    for (final node in body.childElements) {
      final block = switch (node.name.qualified) {
        'w:p' => _paragraph(node, links),
        'w:tbl' => _table(node, links),
        _ => null,
      };
      if (block == null || block.text.isEmpty) continue;
      blocks.add(block);
      length += block.text.length;
      if (length > maxCharacters) {
        truncated = true;
        break;
      }
    }
    return NexDocxText(_join(blocks), truncated: truncated);
  }

  /// Blocks, joined the way Markdown wants them: a blank line between
  /// paragraphs, a single newline between the items of one list.
  ///
  /// The difference is visible. A blank line between two `-` lines makes a
  /// *loose* list, which CommonMark renders with a paragraph inside every
  /// item — a bulleted list with a line of air under each bullet, which is not
  /// what the document looked like.
  static String _join(List<_Block> blocks) {
    final out = StringBuffer();
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) {
        out.write(blocks[i].isListItem && blocks[i - 1].isListItem ? '\n' : '\n\n');
      }
      out.write(blocks[i].text);
    }
    return out.toString();
  }

  static String? _entry(Archive archive, String name) {
    for (final file in archive) {
      if (!file.isFile || file.name != name) continue;
      final content = file.readBytes();
      if (content == null) return null;
      try {
        return utf8.decode(content, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// `r:id` to URL, for the hyperlinks in the document.
  ///
  /// External targets only. The same file also maps every image, font and
  /// header to a path inside the zip, and turning one of those into a link
  /// would produce a link to a file nobody can open.
  static Map<String, String> _relationships(String? source) {
    if (source == null) return const {};
    final links = <String, String>{};
    try {
      final document = XmlDocument.parse(source);
      for (final relationship in document.rootElement.childElements) {
        if (relationship.getAttribute('TargetMode') != 'External') continue;
        final id = relationship.getAttribute('Id');
        final target = relationship.getAttribute('Target');
        if (id == null || target == null) continue;
        if (id.isEmpty || target.isEmpty) continue;
        links[id] = target;
      }
    } catch (_) {
      return const {};
    }
    return links;
  }

  static _Block? _paragraph(XmlElement paragraph, Map<String, String> links) {
    final text = _inline(paragraph, links).trim();
    if (text.isEmpty) return null;

    final properties = paragraph.getElement('w:pPr');
    final style =
        properties?.getElement('w:pStyle')?.getAttribute('w:val') ?? '';
    final heading = _headingLevel(style);
    if (heading != null) {
      return _Block('${'#' * heading} $text');
    }
    if (style.toLowerCase().contains('quote')) return _Block('> $text');
    // Numbering is a reference into `word/numbering.xml`, which says whether
    // the list is bulleted or numbered and at what depth. That file is not
    // read: every item becomes a bullet, which is right for most documents and
    // wrong only about the shape of the marker. Reading it properly is a
    // larger piece of work than the difference has earned.
    if (properties?.getElement('w:numPr') != null) {
      return _Block('- $text', isListItem: true);
    }
    return _Block(text);
  }

  static int? _headingLevel(String style) {
    final name = style.toLowerCase().replaceAll(' ', '');
    if (name == 'title') return 1;
    if (name == 'subtitle') return 2;
    final match = RegExp(r'^heading(\d)$').firstMatch(name);
    if (match == null) return null;
    final level = int.parse(match.group(1)!);
    return level < 1 ? 1 : (level > 6 ? 6 : level);
  }

  /// The text of one paragraph or cell, with its runs' formatting applied.
  static String _inline(XmlElement parent, Map<String, String> links) {
    final out = StringBuffer();
    for (final child in parent.childElements) {
      switch (child.name.qualified) {
        case 'w:r':
          out.write(_run(child));
        case 'w:hyperlink':
          final label = _inline(child, links).trim();
          if (label.isEmpty) continue;
          final id = child.getAttribute('r:id');
          final href = id == null ? null : links[id];
          // A hyperlink with no external target is an internal bookmark —
          // a cross-reference to a heading in the same document. The words
          // survive; there is nowhere for the link to go.
          out.write(href == null ? label : '[$label]($href)');
        // Structured-document tags, smart tags and tracked *insertions* all
        // wrap runs that are part of the text. `w:del` is deliberately absent:
        // a tracked deletion's words are the ones somebody took out.
        case 'w:sdt':
        case 'w:sdtContent':
        case 'w:smartTag':
        case 'w:ins':
          out.write(_inline(child, links));
      }
    }
    return out.toString();
  }

  static String _run(XmlElement run) {
    final buffer = StringBuffer();
    for (final child in run.childElements) {
      switch (child.name.qualified) {
        case 'w:t':
          buffer.write(child.innerText);
        case 'w:tab':
          buffer.write(' ');
        // A shift-enter break inside a paragraph. Two spaces before the
        // newline is CommonMark's hard break; a bare newline would be folded
        // back into a space, which is the thing the author was avoiding.
        case 'w:br':
          buffer.write('  \n');
        case 'w:noBreakHyphen':
          buffer.write('-');
      }
    }
    var text = _escape(buffer.toString());
    if (text.trim().isEmpty) return text;
    final properties = run.getElement('w:rPr');
    if (properties == null) return text;
    // Applied outward, so bold-and-italic comes out as `**_x_**` rather than
    // interleaved — which no parser reads as both.
    if (_isOn(properties, 'w:strike') || _isOn(properties, 'w:dstrike')) {
      text = _wrap(text, '~~');
    }
    if (_isOn(properties, 'w:i')) text = _wrap(text, '_');
    if (_isOn(properties, 'w:b')) text = _wrap(text, '**');
    return text;
  }

  /// Whether a run property is switched on.
  ///
  /// Present means on unless it says otherwise: Word writes `<w:b/>` for bold
  /// and `<w:b w:val="0"/>` to turn it back off inside a style that had it.
  static bool _isOn(XmlElement properties, String tag) {
    final element = properties.getElement(tag);
    if (element == null) return false;
    final value = element.getAttribute('w:val');
    return value != '0' && value != 'false' && value != 'off';
  }

  /// Puts the markers around the words and leaves the spaces outside them.
  ///
  /// The same rule the formatting menu follows, for the same reason: `** x **`
  /// is not bold in any parser, and a Word run very often ends with the space
  /// before the next one.
  static String _wrap(String text, String marker) {
    var start = 0;
    var end = text.length;
    while (start < end && _isSpace(text[start])) {
      start++;
    }
    while (end > start && _isSpace(text[end - 1])) {
      end--;
    }
    if (start >= end) return text;
    return '${text.substring(0, start)}$marker'
        '${text.substring(start, end)}'
        '$marker${text.substring(end)}';
  }

  static bool _isSpace(String char) =>
      char == ' ' || char == '\t' || char == '\n' || char == '\r';

  /// Stops the document's own punctuation from being read as markup.
  ///
  /// A price list that says `2 * 3` and a filename with an underscore in it
  /// both arrive here as ordinary words, and both would come out mangled
  /// without this. The escapes are invisible once rendered, which is the only
  /// place this text is ever read.
  static String _escape(String text) => text.replaceAllMapped(
    RegExp(r'([\\`*_\[\]<>#|])'),
    (match) => '\\${match[1]}',
  );

  static _Block? _table(XmlElement table, Map<String, String> links) {
    final rows = <List<String>>[];
    for (final row in table.findElements('w:tr')) {
      final cells = <String>[
        for (final cell in row.findElements('w:tc'))
          [
                for (final paragraph in cell.findElements('w:p'))
                  _inline(paragraph, links).trim(),
              ]
              .where((text) => text.isNotEmpty)
              .join(' ')
              // A cell is one line of a Markdown table whatever it was in
              // Word, so its own breaks become spaces.
              .replaceAll(RegExp(r'\s*\n\s*'), ' '),
      ];
      if (cells.isNotEmpty) rows.add(cells);
    }
    if (rows.isEmpty) return null;
    final columns = rows.fold<int>(
      0,
      (widest, row) => row.length > widest ? row.length : widest,
    );
    if (columns == 0) return null;

    String line(List<String> cells) => '| ${[
      for (var i = 0; i < columns; i++) i < cells.length ? cells[i] : '',
    ].join(' | ')} |';

    final out = StringBuffer()
      ..writeln(line(rows.first))
      // Markdown has no table without a header, so the first row becomes one.
      // Word tables usually have one; the ones that do not lose a row's worth
      // of emphasis and keep all their words.
      ..write('|${List.filled(columns, ' --- ').join('|')}|');
    for (final row in rows.skip(1)) {
      out
        ..write('\n')
        ..write(line(row));
    }
    return _Block(out.toString());
  }
}

/// A document read out of a `.docx`.
class NexDocxText {
  const NexDocxText(this.markdown, {required this.truncated});

  final String markdown;

  /// Whether the reader stopped before the end of the document. Said out loud
  /// by the caller: a document that ends early with no explanation reads as a
  /// document that is that short.
  final bool truncated;
}

/// One block of Markdown, and whether it is an item of a list.
class _Block {
  const _Block(this.text, {this.isListItem = false});

  final String text;
  final bool isListItem;
}
