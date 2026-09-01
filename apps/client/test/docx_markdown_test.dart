import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/documents/docx_markdown.dart';

/// A `.docx` is a zip of XML, so the fixtures here are built rather than
/// stored: a checked-in binary would be a black box, and every one of these
/// cases is about one specific piece of Word's markup.
void main() {
  /// A `.docx` holding [body] as the contents of `w:body`.
  List<int> docx(String body, {String? relationships}) {
    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('word/document.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<w:document
    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>$body</w:body>
</w:document>
''');
    if (relationships != null) {
      add('word/_rels/document.xml.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships
    xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
$relationships
</Relationships>
''');
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// One paragraph of one run.
  String para(String text, {String? style, String? runProperties}) =>
      '<w:p>'
      '${style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>'}'
      '<w:r>${runProperties ?? ''}<w:t>$text</w:t></w:r>'
      '</w:p>';

  String? read(List<int> bytes) => NexDocx.read(bytes)?.markdown;

  test('paragraphs become paragraphs', () {
    expect(read(docx('${para('One.')}${para('Two.')}')), 'One.\n\nTwo.');
  });

  test('a heading style becomes a heading', () {
    expect(
      read(docx(para('Chapter', style: 'Heading1'))),
      '# Chapter',
    );
    expect(read(docx(para('Part', style: 'Heading3'))), '### Part');
    // Word's own "Title" is the top of the ramp under another name.
    expect(read(docx(para('Name', style: 'Title'))), '# Name');
  });

  test('bold, italic and strikethrough survive', () {
    expect(
      read(docx(para('loud', runProperties: '<w:rPr><w:b/></w:rPr>'))),
      '**loud**',
    );
    expect(
      read(docx(para('soft', runProperties: '<w:rPr><w:i/></w:rPr>'))),
      '_soft_',
    );
    expect(
      read(docx(para('gone', runProperties: '<w:rPr><w:strike/></w:rPr>'))),
      '~~gone~~',
    );
    // Both at once, applied outward rather than interleaved.
    expect(
      read(docx(para('x', runProperties: '<w:rPr><w:b/><w:i/></w:rPr>'))),
      '**_x_**',
    );
  });

  test('a property switched off in a style is off', () {
    // Word writes `<w:b w:val="0"/>` to cancel bold inherited from a style.
    expect(
      read(docx(para('plain', runProperties: '<w:rPr><w:b w:val="0"/></w:rPr>'))),
      'plain',
    );
  });

  test('the space between two runs stays outside the markers', () {
    // `** bold **` is not bold in any parser, and a Word run very often ends
    // with the space before the next one.
    final body =
        '<w:p>'
        '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">loud </w:t></w:r>'
        '<w:r><w:t>then quiet</w:t></w:r>'
        '</w:p>';
    expect(read(docx(body)), '**loud** then quiet');
  });

  test('numbered paragraphs become one tight list', () {
    // Separated by blank lines they would be a *loose* list, which renders
    // with a paragraph inside every item — air under every bullet.
    String item(String text) =>
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/>'
        '</w:numPr></w:pPr><w:r><w:t>$text</w:t></w:r></w:p>';
    expect(
      read(docx('${item('First')}${item('Second')}')),
      '- First\n- Second',
    );
  });

  test('a hyperlink with an external target becomes a link', () {
    final body =
        '<w:p><w:hyperlink r:id="rId7">'
        '<w:r><w:t>the docs</w:t></w:r>'
        '</w:hyperlink></w:p>';
    const rels =
        '<Relationship Id="rId7" Target="https://x.dev" TargetMode="External" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/hyperlink"/>';
    expect(
      read(docx(body, relationships: rels)),
      '[the docs](https://x.dev)',
    );
  });

  test('an internal cross-reference keeps its words and loses its link', () {
    // It points at a bookmark in the same document. There is nowhere to go.
    final body =
        '<w:p><w:hyperlink w:anchor="_Toc1">'
        '<w:r><w:t>see above</w:t></w:r>'
        '</w:hyperlink></w:p>';
    expect(read(docx(body)), 'see above');
  });

  test('a table becomes a Markdown table', () {
    String cell(String text) => '<w:tc>${para(text)}</w:tc>';
    final body =
        '<w:tbl>'
        '<w:tr>${cell('City')}${cell('Total')}</w:tr>'
        '<w:tr>${cell('Shiraz')}${cell('3')}</w:tr>'
        '</w:tbl>';
    expect(
      read(docx(body)),
      '| City | Total |\n| --- | --- |\n| Shiraz | 3 |',
    );
  });

  test("the document's own punctuation is not read as markup", () {
    // A price list that says `2 * 3` and a filename with underscores both
    // arrive as ordinary words and would come out mangled without escaping.
    expect(read(docx(para('2 * 3 and a_b_c'))), r'2 \* 3 and a\_b\_c');
  });

  test('a tracked deletion is not part of the document', () {
    final body =
        '<w:p>'
        '<w:r><w:t>kept</w:t></w:r>'
        '<w:del><w:r><w:delText>removed</w:delText></w:r></w:del>'
        '<w:ins><w:r><w:t> and added</w:t></w:r></w:ins>'
        '</w:p>';
    expect(read(docx(body)), 'kept and added');
  });

  group('what it refuses', () {
    test('bytes that are not a zip', () {
      expect(NexDocx.read(utf8.encode('not a docx at all')), isNull);
    });

    test('a zip with no document in it', () {
      final archive = Archive();
      final bytes = utf8.encode('hello');
      archive.addFile(ArchiveFile('readme.txt', bytes.length, bytes));
      expect(NexDocx.read(ZipEncoder().encodeBytes(archive)), isNull);
    });

    test('a file past the size cap, without unzipping it', () {
      expect(NexDocx.read(List.filled(NexDocx.maxBytes + 1, 0)), isNull);
    });
  });

  test('a document longer than the cap stops and says so', () {
    // The byte cap cannot stand in for this one: text compresses ten to one,
    // so a small `.docx` can hold a book.
    final long = List.generate(250, (i) => para('${'word ' * 200}$i')).join();
    final read = NexDocx.read(docx(long));
    expect(read, isNotNull);
    expect(read!.truncated, isTrue);
    expect(read.markdown, startsWith('word word'));
    // Everything up to the cap is there, and not much more.
    expect(read.markdown.length, greaterThan(NexDocx.maxCharacters));
    expect(read.markdown.length, lessThan(NexDocx.maxCharacters * 2));
  });
}
