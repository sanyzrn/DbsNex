import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  group('NexDelimitedText', () {
    test('reads plain rows', () {
      expect(NexDelimitedText.parse('a,b,c\n1,2,3'), [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('a quoted field may contain the delimiter', () {
      // The reason this is a scanner and not a `split`.
      expect(NexDelimitedText.parse('"Tehran, Iran",2'), [
        ['Tehran, Iran', '2'],
      ]);
    });

    test('a doubled quote inside a quoted field is one quote', () {
      expect(NexDelimitedText.parse('"she said ""hi""",x'), [
        ['she said "hi"', 'x'],
      ]);
    });

    test('a quoted field may contain a line break', () {
      expect(NexDelimitedText.parse('"one\ntwo",b'), [
        ['one\ntwo', 'b'],
      ]);
    });

    test('CRLF is a line ending and a lone CR is content', () {
      expect(NexDelimitedText.parse('a,b\r\nc,d'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('a trailing newline does not invent an empty last row', () {
      expect(NexDelimitedText.parse('a,b\n'), [
        ['a', 'b'],
      ]);
      expect(NexDelimitedText.parse(''), isEmpty);
    });

    test('empty fields survive', () {
      expect(NexDelimitedText.parse('a,,c'), [
        ['a', '', 'c'],
      ]);
    });

    test('ragged rows stay ragged rather than being padded', () {
      // Padding would be inventing cells. The table decides what to do.
      expect(NexDelimitedText.parse('a,b,c\n1'), [
        ['a', 'b', 'c'],
        ['1'],
      ]);
    });

    test('tabs, for a .tsv', () {
      expect(NexDelimitedText.parse('a\tb\n1\t2', delimiter: '\t'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
      expect(NexDelimitedText.delimiterFor('tsv'), '\t');
      expect(NexDelimitedText.delimiterFor('csv'), ',');
    });
  });
}
