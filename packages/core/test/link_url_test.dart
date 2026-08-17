import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  group('normaliseUrl', () {
    test('adds https to what people actually type', () {
      expect(normaliseUrl('example.com'), 'https://example.com');
      expect(normaliseUrl('example.com/a/b'), 'https://example.com/a/b');
      expect(normaliseUrl('  example.com  '), 'https://example.com');
    });

    test('leaves an explicit scheme alone', () {
      expect(normaliseUrl('http://example.com/x'), 'http://example.com/x');
      expect(
        normaliseUrl('https://example.com/x?q=1#f'),
        'https://example.com/x?q=1#f',
      );
    });

    test('unwraps a link the sending app bracketed', () {
      expect(normaliseUrl('<https://example.com>'), 'https://example.com');
    });

    test('refuses schemes a bookmark is never made of', () {
      // A URL launcher would happily act on all three. None of them is a page.
      expect(normaliseUrl('javascript:alert(1)'), isNull);
      expect(normaliseUrl('data:text/html,<h1>hi</h1>'), isNull);
      expect(normaliseUrl('file:///etc/passwd'), isNull);
    });

    test('refuses things that are not URLs at all', () {
      expect(normaliseUrl(''), isNull);
      expect(normaliseUrl('   '), isNull);
      expect(normaliseUrl('https://'), isNull);
      // No dot and not localhost — a bare word is a note, not a link.
      expect(normaliseUrl('reminder'), isNull);
      // Whitespace means this is a sentence someone pasted, not an address.
      expect(normaliseUrl('go to example.com later'), isNull);
    });

    test('localhost is a real host', () {
      expect(
        normaliseUrl('http://localhost:8080/x'),
        'http://localhost:8080/x',
      );
    });
  });

  group('urlHost', () {
    test('is the part worth showing beside a title', () {
      expect(urlHost('https://www.example.com/a/b?utm=1'), 'example.com');
      expect(urlHost('https://news.example.co.uk/x'), 'news.example.co.uk');
    });

    test('answers null rather than throwing on nothing useful', () {
      expect(urlHost(null), isNull);
      expect(urlHost('not a url'), isNull);
    });
  });
}
