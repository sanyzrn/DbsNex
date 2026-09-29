import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:nex_core/nex_core.dart';
import 'package:xml/xml.dart';

import 'docx_markdown.dart';

/// Turns a file that is mostly words into the text of a note.
///
/// One direction only, on purpose. A note can become a Markdown file (see
/// `NexServices.convertMarkdown`) and nothing else, because Markdown is the
/// one format a note already *is*; any other target would be the app
/// pretending to be a word processor. The other way round is different:
/// somebody shares a `.docx` or an old `.txt` into Nex, and what they
/// actually want is the words, searchable and editable like everything else
/// they wrote.
///
/// What each format keeps:
///
/// - plain text, logs, Markdown: exactly as written. Text that is not valid
///   UTF-8 is read as Windows-1256, the encoding most older Persian files on
///   Windows use, which also keeps Western accented letters in place.
/// - `.docx` and `.odt`: headings, lists, emphasis and tables as Markdown.
/// - `.doc` (Word 97–2003) and `.rtf`: the text and its paragraphs. Their
///   formatting is not worth a converter the size of Word.
/// - `.html` and `.epub`: headings, lists and paragraphs.
/// - `.csv`/`.tsv`: a Markdown table.
/// - source and configuration files: a fenced code block, so the note still
///   shows them in a fixed-width font.
///
/// PDF is deliberately absent: its text has no reliable reading order, and a
/// conversion that scrambles paragraphs is worse than keeping the file.
abstract final class NexTextImport {
  /// Files larger than this are not read. Matches the Markdown import limit.
  static const maxBytes = 16 * 1024 * 1024;

  /// A note longer than this stops being something anyone edits.
  static const maxCharacters = 2 * 1024 * 1024;

  static const _documents = {
    'docx',
    'doc',
    'odt',
    'rtf',
    'html',
    'htm',
    'epub',
  };

  /// Whether a file at [path] (or of [mimeType]) can become a note.
  static bool canConvert(String? path, {String? mimeType}) {
    final extension = NexFileKinds.extensionOf(path ?? '');
    if (_documents.contains(extension)) return true;
    return switch (NexFileKinds.of(path: path, mimeType: mimeType)) {
      NexFileKind.markdown ||
      NexFileKind.plainText ||
      NexFileKind.table ||
      NexFileKind.code => true,
      _ => false,
    };
  }

  /// Reads [bytes] off the main thread. Null when nothing readable was found.
  static Future<String?> extract(Uint8List bytes, String path) =>
      Isolate.run(() => extractSync(bytes, path));

  static String? extractSync(Uint8List bytes, String path) {
    if (bytes.length > maxBytes) return null;
    final extension = NexFileKinds.extensionOf(path);
    String? text;
    try {
      text = switch (extension) {
        'docx' => NexDocx.read(bytes)?.markdown,
        'doc' => _WordBinary.read(bytes),
        'odt' => _odt(bytes),
        'rtf' => _Rtf.read(bytes),
        'html' || 'htm' => htmlToText(decodeText(bytes)),
        'epub' => _epub(bytes),
        _ => _byKind(bytes, path, extension),
      };
    } catch (_) {
      return null;
    }
    if (text == null) return null;
    final tidy = _tidy(text);
    if (tidy.isEmpty) return null;
    return tidy.length > maxCharacters
        ? tidy.substring(0, maxCharacters)
        : tidy;
  }

  static String? _byKind(Uint8List bytes, String path, String extension) {
    final text = decodeText(bytes);
    return switch (NexFileKinds.of(path: path)) {
      NexFileKind.table => _table(text, extension == 'tsv' ? '\t' : ','),
      NexFileKind.code => '```$extension\n${text.trimRight()}\n```',
      NexFileKind.markdown || NexFileKind.plainText => text,
      _ => null,
    };
  }

  /// UTF-8 (with or without a BOM), UTF-16 with a BOM, or Windows-1256.
  static String decodeText(List<int> bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _utf16(bytes.sublist(2), littleEndian: true);
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _utf16(bytes.sublist(2), littleEndian: false);
      }
    }
    final start =
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? 3
        : 0;
    try {
      return utf8.decode(bytes.sublist(start));
    } on FormatException {
      return _singleByte(bytes, _cp1256);
    }
  }

  static String _utf16(List<int> bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  static String _singleByte(List<int> bytes, List<int> upper) =>
      String.fromCharCodes([
        for (final b in bytes) b < 0x80 ? b : upper[b - 0x80],
      ]);

  static String _table(String text, String delimiter) {
    final rows = NexDelimitedText.parse(
      text,
      delimiter: delimiter,
    ).where((row) => row.any((cell) => cell.trim().isNotEmpty)).toList();
    if (rows.isEmpty) return '';
    final width = rows.map((r) => r.length).reduce(math.max);
    String cell(String value) =>
        value.replaceAll('|', r'\|').replaceAll(RegExp(r'\s*\n\s*'), ' ');
    String line(List<String> row) =>
        '| ${[for (var i = 0; i < width; i++) cell(i < row.length ? row[i] : '')].join(' | ')} |';
    return [
      line(rows.first),
      '|${List.filled(width, ' --- ').join('|')}|',
      for (final row in rows.skip(1)) line(row),
    ].join('\n');
  }

  static String? _zipText(Archive archive, String name) {
    for (final file in archive) {
      if (!file.isFile || file.name != name) continue;
      final content = file.readBytes();
      return content == null
          ? null
          : utf8.decode(content, allowMalformed: true);
    }
    return null;
  }

  static String? _odt(Uint8List bytes) {
    final content = _zipText(ZipDecoder().decodeBytes(bytes), 'content.xml');
    if (content == null) return null;
    final document = XmlDocument.parse(content);
    final body = document.descendants.whereType<XmlElement>().where(
      (e) => e.name.qualified == 'office:text',
    );
    if (body.isEmpty) return null;
    final out = StringBuffer();
    void blocks(XmlElement element, {int depth = 0}) {
      for (final child in element.childElements) {
        switch (child.name.qualified) {
          case 'text:h':
            final level =
                int.tryParse(child.getAttribute('text:outline-level') ?? '') ??
                1;
            out.writeln('${'#' * level.clamp(1, 6)} ${_odtInline(child)}');
            out.writeln();
          case 'text:p':
            out.writeln(_odtInline(child));
            out.writeln();
          case 'text:list':
            _odtList(child, out, 0);
            out.writeln();
          case 'table:table':
            final rows = child.descendants.whereType<XmlElement>().where(
              (e) => e.name.qualified == 'table:table-row',
            );
            var first = true;
            for (final row in rows) {
              final cells = row.childElements
                  .where((e) => e.name.qualified == 'table:table-cell')
                  .map((c) => _odtInline(c).replaceAll('|', r'\|'))
                  .toList();
              out.writeln('| ${cells.join(' | ')} |');
              if (first) {
                out.writeln(
                  '|${List.filled(cells.length, ' --- ').join('|')}|',
                );
                first = false;
              }
            }
            out.writeln();
          case 'text:section' || 'text:soft-page-break':
            blocks(child, depth: depth);
        }
      }
    }

    blocks(body.first);
    return out.toString();
  }

  static void _odtList(XmlElement list, StringBuffer out, int depth) {
    for (final item in list.childElements.where(
      (e) => e.name.qualified == 'text:list-item',
    )) {
      for (final part in item.childElements) {
        if (part.name.qualified == 'text:list') {
          _odtList(part, out, depth + 1);
        } else {
          out.writeln('${'  ' * depth}- ${_odtInline(part)}');
        }
      }
    }
  }

  static String _odtInline(XmlElement element) {
    final out = StringBuffer();
    void walk(XmlNode node) {
      if (node is XmlText) {
        out.write(node.value);
      } else if (node is XmlElement) {
        switch (node.name.qualified) {
          case 'text:s':
            out.write(
              ' ' * (int.tryParse(node.getAttribute('text:c') ?? '') ?? 1),
            );
          case 'text:tab':
            out.write('\t');
          case 'text:line-break':
            out.write('\n');
          case 'text:note' || 'office:annotation':
            break;
          default:
            node.children.forEach(walk);
        }
      }
    }

    element.children.forEach(walk);
    return out.toString().trim();
  }

  static String? _epub(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String? read(String name) => _zipText(archive, name);

    final container = read('META-INF/container.xml');
    if (container == null) return null;
    final opfPath = XmlDocument.parse(container).descendants
        .whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'rootfile')
        .getAttribute('full-path');
    if (opfPath == null) return null;
    final opf = XmlDocument.parse(read(opfPath) ?? '');
    final base = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';
    final manifest = {
      for (final item in opf.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'item',
      ))
        item.getAttribute('id'): item.getAttribute('href'),
    };
    final out = StringBuffer();
    for (final ref in opf.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'itemref',
    )) {
      final href = manifest[ref.getAttribute('idref')];
      if (href == null) continue;
      final page = read(base + Uri.decodeFull(href));
      if (page == null) continue;
      out.writeln(htmlToText(page));
      out.writeln();
      if (out.length > maxCharacters) break;
    }
    return out.toString();
  }

  /// HTML to readable text with Markdown headings and list markers.
  static String htmlToText(String html) {
    var s = html
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .replaceAll(
          RegExp(
            r'<(script|style|head|noscript|svg)\b.*?</\1\s*>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        // Whitespace in HTML source is not layout; the tags are.
        .replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAllMapped(
      RegExp(r'<h([1-6])\b[^>]*>', caseSensitive: false),
      (m) => '\n\n${'#' * int.parse(m[1]!)} ',
    );
    s = s
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n- ')
        .replaceAll(RegExp(r'<hr\b[^>]*>', caseSensitive: false), '\n\n---\n\n')
        .replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), ' | ')
        .replaceAll(
          RegExp(
            r'</?(p|div|section|article|blockquote|tr|table|ul|ol|h[1-6]|header|footer|pre|dl|dt|dd)\b[^>]*>',
            caseSensitive: false,
          ),
          '\n\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');
    s = _entities(s);
    return s.split('\n').map((line) => line.trim()).join('\n');
  }

  static String _entities(String s) =>
      s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
        final e = m[1]!;
        if (e.startsWith('#x') || e.startsWith('#X')) {
          return String.fromCharCode(int.parse(e.substring(2), radix: 16));
        }
        if (e.startsWith('#')) {
          return String.fromCharCode(int.parse(e.substring(1)));
        }
        return switch (e) {
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'apos' => "'",
          'nbsp' => '\u00A0',
          'zwnj' => '\u200C',
          'zwj' => '\u200D',
          'rlm' => '\u200F',
          'lrm' => '\u200E',
          'mdash' => '—',
          'ndash' => '–',
          'hellip' => '…',
          'laquo' => '«',
          'raquo' => '»',
          'copy' => '©',
          _ => m[0]!,
        };
      });

  /// Normalised line endings, no trailing spaces, at most one blank line in a
  /// row.
  static String _tidy(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Windows-1256, bytes 0x80–0xFF.
const _cp1256 = [
  0x20AC, 0x067E, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0679, 0x2039, 0x0152, 0x0686, 0x0698, 0x0688,
  0x06AF, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x06A9, 0x2122, 0x0691, 0x203A, 0x0153, 0x200C, 0x200D, 0x06BA,
  0x00A0, 0x060C, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7,
  0x00A8, 0x00A9, 0x06BE, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7,
  0x00B8, 0x00B9, 0x061B, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x061F,
  0x06C1, 0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627,
  0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F,
  0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x00D7,
  0x0637, 0x0638, 0x0639, 0x063A, 0x0640, 0x0641, 0x0642, 0x0643,
  0x00E0, 0x0644, 0x00E2, 0x0645, 0x0646, 0x0647, 0x0648, 0x00E7,
  0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x0649, 0x064A, 0x00EE, 0x00EF,
  0x064B, 0x064C, 0x064D, 0x064E, 0x00F4, 0x064F, 0x0650, 0x00F7,
  0x0651, 0x00F9, 0x0652, 0x00FB, 0x00FC, 0x200E, 0x200F, 0x06D2,
];

/// Windows-1252, bytes 0x80–0xFF. The five holes read as Latin-1.
final _cp1252 = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
  for (var b = 0xA0; b <= 0xFF; b++) b,
];

List<int> _codepage(int page) => page == 1256 ? _cp1256 : _cp1252;

/// Rich Text Format: the words, paragraphs and tabs, in whichever code page
/// the file declares, plus `\u` escapes.
abstract final class _Rtf {
  /// Groups whose contents are not the document's text.
  static const _skip = {
    'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'object', //
    'header', 'headerl', 'headerr', 'headerf', 'footer', 'footerl',
    'footerr', 'footerf', 'fldinst', 'themedata', 'colorschememapping',
    'datastore', 'latentstyles', 'xmlnstbl', 'listtable',
    'listoverridetable', 'rsidtbl', 'generator', 'mmathPr', 'pgdsctbl',
    'filetbl', 'revtbl', 'listtext', 'pntext', 'bkmkstart', 'bkmkend',
    'factoidname', 'userprops', 'docvar', 'template', 'wgrffmtfilter',
  };

  static final _letter = RegExp('[a-zA-Z]');
  static final _word = RegExp(r'([a-zA-Z]+)(-?\d+)? ?');

  static String? read(Uint8List bytes) {
    final source = latin1.decode(bytes);
    if (!source.startsWith('{\\rtf')) return null;
    final out = StringBuffer();
    // (skipping, unicode-skip count, code page) per group.
    final stack = <(bool, int, int)>[];
    var skipping = false;
    var ucSkip = 1;
    var page = 1252;
    var pendingSkip = 0;
    void emit(String text) {
      if (skipping) return;
      if (pendingSkip > 0) {
        pendingSkip--;
        return;
      }
      out.write(text);
    }

    var i = 0;
    while (i < source.length) {
      final c = source[i];
      if (c == '{') {
        stack.add((skipping, ucSkip, page));
        i++;
      } else if (c == '}') {
        if (stack.isNotEmpty) (skipping, ucSkip, page) = stack.removeLast();
        pendingSkip = 0;
        i++;
      } else if (c == '\\') {
        i++;
        if (i >= source.length) break;
        final next = source[i];
        if (next == "'") {
          final hex = int.tryParse(
            source.substring(i + 1, math.min(i + 3, source.length)),
            radix: 16,
          );
          i += 3;
          if (hex != null) {
            emit(
              String.fromCharCode(
                hex < 0x80 ? hex : _codepage(page)[hex - 0x80],
              ),
            );
          }
        } else if (next == '*') {
          skipping = true;
          i++;
        } else if (next == '\\' || next == '{' || next == '}') {
          emit(next);
          i++;
        } else if (next == '~') {
          emit('\u00A0');
          i++;
        } else if (next == '_') {
          emit('-');
          i++;
        } else if (next == '\n' || next == '\r') {
          emit('\n');
          i++;
        } else if (_letter.hasMatch(next)) {
          final match = _word.matchAsPrefix(source, i)!;
          i = match.end;
          final word = match[1]!;
          final arg = int.tryParse(match[2] ?? '');
          if (_skip.contains(word)) {
            skipping = true;
            continue;
          }
          switch (word) {
            case 'par' || 'line' || 'row' || 'sect' || 'page':
              emit('\n');
            case 'tab' || 'cell':
              emit('\t');
            case 'uc':
              ucSkip = arg ?? 1;
            case 'ansicpg':
              page = arg ?? 1252;
            case 'u':
              if (arg != null) {
                emit(String.fromCharCode(arg < 0 ? arg + 65536 : arg));
                pendingSkip = ucSkip;
              }
            case 'emdash':
              emit('—');
            case 'endash':
              emit('–');
            case 'bullet':
              emit('•');
            case 'lquote':
              emit('‘');
            case 'rquote':
              emit('’');
            case 'ldblquote':
              emit('“');
            case 'rdblquote':
              emit('”');
            case 'bin':
              i += arg ?? 0;
          }
        } else {
          i++;
        }
      } else {
        if (c != '\r' && c != '\n') emit(c);
        i++;
      }
    }
    return out.toString();
  }
}

/// Word 97–2003 (`.doc`): the main document's text from its piece table.
///
/// The file is an OLE compound document holding a `WordDocument` stream and
/// a table stream; the text itself sits in pieces the table describes, each
/// either UTF-16 or single-byte Windows-1252. Formatting lives elsewhere and
/// is not read.
abstract final class _WordBinary {
  static String? read(Uint8List bytes) {
    final file = _Cfb.parse(bytes);
    if (file == null) return null;
    final word = file.stream('WordDocument');
    if (word == null || word.length < 0x1AA) return null;
    final data = ByteData.sublistView(word);
    if (data.getUint16(0, Endian.little) != 0xA5EC) return null;
    final flags = data.getUint16(0x0A, Endian.little);
    if (flags & 0x0100 != 0) return null; // Encrypted.
    final table = file.stream(flags & 0x0200 != 0 ? '1Table' : '0Table');
    if (table == null) return null;
    final ccpText = data.getUint32(0x4C, Endian.little);
    final fcClx = data.getUint32(0x1A2, Endian.little);
    final lcbClx = data.getUint32(0x1A6, Endian.little);
    if (fcClx + lcbClx > table.length) return null;
    final clx = ByteData.sublistView(table, fcClx, fcClx + lcbClx);
    var at = 0;
    while (at < clx.lengthInBytes && clx.getUint8(at) == 0x01) {
      at += 3 + clx.getInt16(at + 1, Endian.little);
    }
    if (at >= clx.lengthInBytes || clx.getUint8(at) != 0x02) return null;
    final lcb = clx.getUint32(at + 1, Endian.little);
    final plc = at + 5;
    final count = (lcb - 4) ~/ 12;
    final out = StringBuffer();
    for (var n = 0; n < count; n++) {
      final start = clx.getUint32(plc + n * 4, Endian.little);
      if (start >= ccpText) break;
      final end = math.min(
        clx.getUint32(plc + (n + 1) * 4, Endian.little),
        ccpText,
      );
      final pcd = plc + (count + 1) * 4 + n * 8;
      final fcRaw = clx.getUint32(pcd + 2, Endian.little);
      final compressed = fcRaw & 0x40000000 != 0;
      final length = end - start;
      if (compressed) {
        final offset = (fcRaw & 0x3FFFFFFF) ~/ 2;
        if (offset + length > word.length) return null;
        for (var k = 0; k < length; k++) {
          final b = word[offset + k];
          out.writeCharCode(b < 0x80 ? b : _cp1252[b - 0x80]);
        }
      } else {
        final offset = fcRaw;
        if (offset + length * 2 > word.length) return null;
        for (var k = 0; k < length; k++) {
          out.writeCharCode(data.getUint16(offset + k * 2, Endian.little));
        }
      }
    }
    return _clean(out.toString());
  }

  /// Word's control characters: paragraph and cell marks become line breaks
  /// and tabs, and a field keeps its visible result but not its code.
  static String _clean(String raw) {
    final out = StringBuffer();
    var depth = 0;
    final showing = <bool>[];
    for (final unit in raw.runes) {
      switch (unit) {
        case 0x13:
          depth++;
          showing.add(false);
        case 0x14:
          if (showing.isNotEmpty) showing[showing.length - 1] = true;
        case 0x15:
          if (depth > 0) {
            depth--;
            showing.removeLast();
          }
        default:
          if (showing.isNotEmpty && !showing.last) continue;
          switch (unit) {
            case 0x0D || 0x0B || 0x0C:
              out.write('\n');
            case 0x07:
              out.write('\t');
            case 0x1E:
              out.write('-');
            case 0x01 || 0x08 || 0x1F || 0x05:
              break;
            default:
              out.writeCharCode(unit);
          }
      }
    }
    return out.toString();
  }
}

/// The smallest reader of Microsoft's compound file format that finds a
/// stream by name.
class _Cfb {
  _Cfb(
    this._bytes,
    this._sectorSize,
    this._fat,
    this._miniFat,
    this._entries,
    this._miniStream,
  );

  final Uint8List _bytes;
  final int _sectorSize;
  final List<int> _fat;
  final List<int> _miniFat;
  final List<({String name, int start, int size})> _entries;
  final Uint8List _miniStream;

  static const _end = 0xFFFFFFFE;

  static _Cfb? parse(Uint8List bytes) {
    const signature = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    if (bytes.length < 512) return null;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != signature[i]) return null;
    }
    final header = ByteData.sublistView(bytes);
    final sectorSize = 1 << header.getUint16(0x1E, Endian.little);
    if (sectorSize != 512 && sectorSize != 4096) return null;
    int u32(int offset) => offset + 4 <= bytes.length
        ? header.getUint32(offset, Endian.little)
        : _end;
    Uint8List sector(int n) {
      final start = (n + 1) * sectorSize;
      if (start + sectorSize > bytes.length) throw const FormatException();
      return Uint8List.sublistView(bytes, start, start + sectorSize);
    }

    // The sector allocation table, gathered through the DIFAT.
    final fatSectors = <int>[];
    for (var i = 0; i < 109; i++) {
      final s = u32(0x4C + i * 4);
      if (s < 0xFFFFFFFA) fatSectors.add(s);
    }
    var difat = u32(0x44);
    var guard = 0;
    while (difat < 0xFFFFFFFA && guard++ < 10000) {
      final d = ByteData.sublistView(sector(difat));
      for (var i = 0; i < sectorSize ~/ 4 - 1; i++) {
        final s = d.getUint32(i * 4, Endian.little);
        if (s < 0xFFFFFFFA) fatSectors.add(s);
      }
      difat = d.getUint32(sectorSize - 4, Endian.little);
    }
    final fat = <int>[];
    for (final s in fatSectors) {
      final d = ByteData.sublistView(sector(s));
      for (var i = 0; i < sectorSize ~/ 4; i++) {
        fat.add(d.getUint32(i * 4, Endian.little));
      }
    }
    Uint8List chain(
      int start,
      List<int> table,
      Uint8List Function(int) at,
      int size,
    ) {
      final out = BytesBuilder(copy: false);
      var s = start;
      var steps = 0;
      while (s < 0xFFFFFFFA && s < table.length && steps++ < 1 << 22) {
        out.add(at(s));
        s = table[s];
      }
      final all = out.takeBytes();
      return size >= 0 && size < all.length
          ? Uint8List.sublistView(all, 0, size)
          : all;
    }

    final directory = chain(u32(0x30), fat, sector, -1);
    final entries = <({String name, int start, int size})>[];
    final dir = ByteData.sublistView(directory);
    for (var at = 0; at + 128 <= directory.length; at += 128) {
      final nameLength = dir.getUint16(at + 64, Endian.little);
      final type = dir.getUint8(at + 66);
      if (type == 0 || nameLength < 2 || nameLength > 64) {
        entries.add((name: '', start: _end, size: 0));
        continue;
      }
      final units = [
        for (var i = 0; i < nameLength ~/ 2 - 1; i++)
          dir.getUint16(at + i * 2, Endian.little),
      ];
      entries.add((
        name: String.fromCharCodes(units),
        start: dir.getUint32(at + 116, Endian.little),
        size: dir.getUint32(at + 120, Endian.little),
      ));
    }
    if (entries.isEmpty) return null;
    final miniFatBytes = chain(u32(0x3C), fat, sector, -1);
    final miniFatData = ByteData.sublistView(miniFatBytes);
    final miniFat = [
      for (var i = 0; i + 4 <= miniFatBytes.length; i += 4)
        miniFatData.getUint32(i, Endian.little),
    ];
    final root = entries.first;
    final miniStream = chain(root.start, fat, sector, root.size);
    return _Cfb(bytes, sectorSize, fat, miniFat, entries, miniStream);
  }

  Uint8List? stream(String name) {
    final entry = _entries.skip(1).where((e) => e.name == name).firstOrNull;
    if (entry == null) return null;
    final out = BytesBuilder(copy: false);
    var s = entry.start;
    var steps = 0;
    if (entry.size < 4096) {
      while (s < 0xFFFFFFFA && s < _miniFat.length && steps++ < 1 << 22) {
        final start = s * 64;
        if (start + 64 > _miniStream.length) return null;
        out.add(Uint8List.sublistView(_miniStream, start, start + 64));
        s = _miniFat[s];
      }
    } else {
      while (s < 0xFFFFFFFA && s < _fat.length && steps++ < 1 << 22) {
        final start = (s + 1) * _sectorSize;
        if (start + _sectorSize > _bytes.length) return null;
        out.add(Uint8List.sublistView(_bytes, start, start + _sectorSize));
        s = _fat[s];
      }
    }
    final all = out.takeBytes();
    return all.length < entry.size
        ? null
        : Uint8List.sublistView(all, 0, entry.size);
  }
}
