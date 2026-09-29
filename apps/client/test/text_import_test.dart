import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/documents/text_import.dart';

/// Files that are mostly words become notes; nothing else about them does.
///
/// `test/fixtures/word97.doc` is Apache Tika's `testWORD.doc` (Apache License
/// 2.0), a real Word 97 file: the binary format is not something a test can
/// fake convincingly.
void main() {
  String? read(List<int> bytes, String name) =>
      NexTextImport.extractSync(Uint8List.fromList(bytes), name);

  Uint8List zip(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('what can be converted, and what cannot', () {
    for (final name in [
      'a.txt',
      'a.md',
      'a.log',
      'a.csv',
      'a.doc',
      'a.docx',
      'a.odt',
      'a.rtf',
      'a.html',
      'a.epub',
      'a.json',
    ]) {
      expect(NexTextImport.canConvert(name), isTrue, reason: name);
    }
    for (final name in ['a.pdf', 'a.jpg', 'a.mp3', 'a.zip', 'a.xlsx']) {
      expect(NexTextImport.canConvert(name), isFalse, reason: name);
    }
  });

  test('an older Persian text file is read as Windows-1256', () {
    // "سلام دنيا" / "خط دوم é" in Windows-1256: not valid UTF-8, and read as
    // Latin-1 it was a row of accented nonsense.
    final bytes = [
      0xD3, 0xE1, 0xC7, 0xE3, 0x20, 0xCF, 0xE4, 0xED, 0xC7, 0x0D, 0x0A, //
      0xCE, 0xD8, 0x20, 0xCF, 0xE6, 0xE3, 0x20, 0xE9,
    ];
    expect(read(bytes, 'old.txt'), 'سلام دنيا\nخط دوم é');
    expect(read(utf8.encode('\uFEFFسلام'), 'bom.txt'), 'سلام');
  });

  test('RTF keeps its words, code page and Unicode escapes', () {
    const rtf =
        r"{\rtf1\ansi\ansicpg1256{\fonttbl{\f0 Tahoma;}}{\*\generator x;}"
        r"\pard \'d3\'e1\'c7\'e3 \u1583?\u1606?\u1740?\u1575?\par "
        r"Second \b line\b0\tab end\par}";
    expect(read(latin1.encode(rtf), 'a.rtf'), 'سلام دنیا\nSecond line\tend');
  });

  test('a Word 97 document gives its text, without field codes', () {
    final text = read(
      File('test/fixtures/word97.doc').readAsBytesSync(),
      'word97.doc',
    )!;
    expect(text, startsWith('Sample Word Document Title'));
    expect(text, contains('This document includes text that is BOLD'));
    expect(text, contains('Apache Tika: http://tika.apache.org/'));
    expect(text, isNot(contains('HYPERLINK')));
  });

  test('OpenDocument text keeps headings, lists and tables', () {
    final odt = zip({
      'content.xml':
          '<office:document-content '
          'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
          'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
          'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0">'
          '<office:body><office:text>'
          '<text:h text:outline-level="2">گزارش</text:h>'
          '<text:p>یک<text:s text:c="2"/>دو</text:p>'
          '<text:list><text:list-item><text:p>اول</text:p>'
          '<text:list><text:list-item><text:p>nested</text:p>'
          '</text:list-item></text:list></text:list-item></text:list>'
          '<table:table><table:table-row>'
          '<table:table-cell><text:p>a</text:p></table:table-cell>'
          '<table:table-cell><text:p>b</text:p></table:table-cell>'
          '</table:table-row></table:table>'
          '</office:text></office:body></office:document-content>',
    });
    expect(
      read(odt, 'a.odt'),
      '## گزارش\n\nیک  دو\n\n- اول\n  - nested\n\n| a | b |\n| --- | --- |',
    );
  });

  test('HTML and EPUB become paragraphs, headings and list items', () {
    expect(
      read(
        utf8.encode(
          '<html><head><style>p{}</style></head><body><h1>Title</h1>'
          '<p>One &amp; <b>two</b></p><ul><li>a</li><li>b</li></ul></body>',
        ),
        'a.html',
      ),
      '# Title\n\nOne & two\n\n- a\n- b',
    );
    final epub = zip({
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="OEBPS/c.opf"/>'
          '</rootfiles></container>',
      'OEBPS/c.opf':
          '<package><manifest><item id="x" href="1.xhtml"/></manifest>'
          '<spine><itemref idref="x"/></spine></package>',
      'OEBPS/1.xhtml': '<html><body><h2>فصل</h2><p>متن</p></body></html>',
    });
    expect(read(epub, 'book.epub'), '## فصل\n\nمتن');
  });

  test('a CSV becomes a Markdown table, and code keeps its font', () {
    expect(
      read(utf8.encode('name,amount\n"Rent, flat",100\n'), 'a.csv'),
      '| name | amount |\n| --- | --- |\n| Rent, flat | 100 |',
    );
    expect(read(utf8.encode('{"a": 1}\n'), 'a.json'), '```json\n{"a": 1}\n```');
  });

  test('nothing readable is null, never an empty note', () {
    expect(read(const [], 'a.txt'), isNull);
    expect(read(utf8.encode('not a zip'), 'a.docx'), isNull);
    expect(read(utf8.encode('not ole'), 'a.doc'), isNull);
    expect(read(utf8.encode('plain'), 'a.rtf'), isNull);
  });
}
