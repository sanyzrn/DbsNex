import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  group('web addresses in plain writing', () {
    test('finds the screenshot URL without changing the surrounding note', () {
      const text = 'افزودن امکانات اکو\n\nhttps://realmetaverse.ir/cipher/';
      final link = nexTextLinks(text).single;
      expect(link.url, 'https://realmetaverse.ir/cipher/');
      expect(text.substring(link.start, link.end), link.url);
    });

    test(
      'keeps query, fragment and balanced parentheses, outside punctuation stays text',
      () {
        const text =
            '(https://en.wikipedia.org/wiki/Link_(The_Legend_of_Zelda)), '
            'https://x.dev/a?q=1&b=2#part! www.example.com/،';
        expect(nexTextLinks(text).map((l) => l.url), [
          'https://en.wikipedia.org/wiki/Link_(The_Legend_of_Zelda)',
          'https://x.dev/a?q=1&b=2#part',
          'https://www.example.com/',
        ]);
      },
    );

    test(
      'recognises uppercase schemes and ignores malformed and unsafe links',
      () {
        expect(nexTextLinks('Https://DD.com').single.url, 'https://dd.com');
        expect(
          nexTextLinks(
            'https:// javascript:alert(1) file:///x data:text/html,x',
          ),
          isEmpty,
        );
        expect(
          nexTextLinks('https://x.dev\u200F متن').single.url,
          'https://x.dev',
        );
      },
    );

    test(
      'Persian straight after an address ends it; a Persian path does not',
      () {
        const glued = 'سایت https://example.comسلام را ببین';
        final link = nexTextLinks(glued).single;
        expect(link.url, 'https://example.com');
        expect(glued.substring(link.end), startsWith('سلام'));
        expect(
          nexTextLinks('www.example.irدیدم').single.url,
          'https://www.example.ir',
        );
        expect(
          nexTextLinks('https://fa.wikipedia.org/wiki/ایران').single.url,
          Uri.parse('https://fa.wikipedia.org/wiki/ایران').toString(),
        );
      },
    );
  });

  group('nexYouTubeWatchUrl', () {
    test('every way a video is shared comes back as one watch address', () {
      const watch = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'youtube.com/watch?v=dQw4w9WgXcQ&t=42s',
        'https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ?si=abcdef',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/live/dQw4w9WgXcQ?feature=share',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
        '  https://youtu.be/dQw4w9WgXcQ  ',
      ]) {
        expect(nexYouTubeWatchUrl(url), watch, reason: url);
      }
    });

    test('channels, playlists, other sites and broken ids are not videos', () {
      for (final url in [
        null,
        '',
        'https://www.youtube.com/@somechannel',
        'https://www.youtube.com/playlist?list=PL123',
        'https://www.youtube.com/results?search_query=x',
        'https://www.youtube.com/watch?v=short',
        'https://vimeo.com/123456',
        'https://notyoutube.com/watch?v=dQw4w9WgXcQ',
        'javascript:alert(1)',
      ]) {
        expect(nexYouTubeWatchUrl(url), isNull, reason: url);
      }
    });
  });

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

  group('sharedLink', () {
    test('a bare address from a browser share is a link', () {
      final link = sharedLink('https://example.com/article?id=7')!;
      expect(link.url, 'https://example.com/article?id=7');
      expect(link.words, isNull);
    });

    test('a title line and an address keep the title as words', () {
      final link = sharedLink('یک مقالهٔ خوب\nhttps://example.com/a')!;
      expect(link.url, 'https://example.com/a');
      expect(link.words, 'یک مقالهٔ خوب');
    });

    test('ordinary text with a link in it stays text', () {
      expect(sharedLink('just words'), isNull);
      expect(sharedLink('see https://a.test and https://b.test'), isNull);
      expect(
        sharedLink(
          '${List.filled(40, 'a long paragraph').join(' ')} https://a.test',
        ),
        isNull,
      );
      expect(sharedLink('one\ntwo\nthree\nhttps://a.test'), isNull);
    });
  });
}
