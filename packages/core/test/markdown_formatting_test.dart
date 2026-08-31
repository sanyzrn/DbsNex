import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  group('toggling an inline format', () {
    test('wraps the selection and leaves it selected', () {
      // `one |two| three` -> `one |**two**| three`, with the selection still
      // on the word rather than on the markers.
      final out = NexTextFormatting.toggleInline(
        'one two three',
        4,
        7,
        NexInlineFormat.bold,
      );
      expect(out.text, 'one **two** three');
      expect(out.text.substring(out.start, out.end), 'two');
    });

    test('unwraps when the markers are just outside the selection', () {
      // Which is exactly the state the previous test leaves behind, so
      // pressing the button twice is a no-op.
      final bold = NexTextFormatting.toggleInline(
        'one two three',
        4,
        7,
        NexInlineFormat.bold,
      );
      final plain = NexTextFormatting.toggleInline(
        bold.text,
        bold.start,
        bold.end,
        NexInlineFormat.bold,
      );
      expect(plain.text, 'one two three');
      expect(plain.text.substring(plain.start, plain.end), 'two');
    });

    test('unwraps when the markers are inside the selection', () {
      final out = NexTextFormatting.toggleInline(
        'one **two** three',
        4,
        11,
        NexInlineFormat.bold,
      );
      expect(out.text, 'one two three');
    });

    test('whitespace at the edge of a drag stays outside the markers', () {
      // `** bold **` is not bold in any CommonMark parser — it is two
      // asterisks, a word, and two more. A drag that overshoots a word by a
      // space is the ordinary way to select one.
      final out = NexTextFormatting.toggleInline(
        'one two three',
        3,
        8,
        NexInlineFormat.bold,
      );
      expect(out.text, 'one **two** three');
    });

    test('each format writes its own marker', () {
      String wrap(NexInlineFormat format) =>
          NexTextFormatting.toggleInline('a word b', 2, 6, format).text;
      expect(wrap(NexInlineFormat.bold), 'a **word** b');
      expect(wrap(NexInlineFormat.italic), 'a _word_ b');
      expect(wrap(NexInlineFormat.strikethrough), 'a ~~word~~ b');
      expect(wrap(NexInlineFormat.mono), 'a `word` b');
    });

    test('a collapsed selection changes nothing', () {
      final out = NexTextFormatting.toggleInline(
        'hello',
        2,
        2,
        NexInlineFormat.bold,
      );
      expect(out.text, 'hello');
    });

    test('a backwards selection is read the right way round', () {
      final out = NexTextFormatting.toggleInline(
        'one two three',
        7,
        4,
        NexInlineFormat.bold,
      );
      expect(out.text, 'one **two** three');
    });

    test('Persian is wrapped the same way', () {
      final out = NexTextFormatting.toggleInline(
        'یک دو سه',
        3,
        5,
        NexInlineFormat.bold,
      );
      expect(out.text, 'یک **دو** سه');
    });
  });

  group('link', () {
    test('turns the selection into a link and selects the whole of it', () {
      final out = NexTextFormatting.link('see docs here', 4, 8, 'https://x.dev');
      expect(out.text, 'see [docs](https://x.dev) here');
      expect(out.text.substring(out.start, out.end), '[docs](https://x.dev)');
    });

    test('an empty URL changes nothing', () {
      final out = NexTextFormatting.link('see docs', 4, 8, '   ');
      expect(out.text, 'see docs');
    });
  });

  group('quote', () {
    test('marks every line the selection touches', () {
      // A block marker, so selecting one word quotes that word's line — not
      // half of it, which would put a `>` in the middle and quote nothing.
      final out = NexTextFormatting.toggleQuote('one\ntwo\nthree', 5, 6);
      expect(out.text, 'one\n> two\nthree');
    });

    test('spans the lines a multi-line selection covers', () {
      final out = NexTextFormatting.toggleQuote('one\ntwo\nthree', 1, 6);
      expect(out.text, '> one\n> two\nthree');
    });

    test('unmarks a block that is already quoted', () {
      final out = NexTextFormatting.toggleQuote('> one\n> two', 0, 10);
      expect(out.text, 'one\ntwo');
    });
  });

  group('clear', () {
    test('removes what the menu can add, and nothing else', () {
      const source =
          'a **bold** and _thin_ and `mono` and ~~gone~~ and [x](https://a.b)';
      final out = NexTextFormatting.clear(source, 0, source.length);
      expect(out.text, 'a bold and thin and mono and gone and x');
    });

    test('leaves a heading someone typed alone', () {
      // "Regular" is the inverse of the other buttons and nothing more.
      // Nobody asked for the heading to go.
      const source = '# Title **b**';
      final out = NexTextFormatting.clear(source, 0, source.length);
      expect(out.text, '# Title b');
    });
  });

  group('NexMarkdownText.plain', () {
    test('strips the markers a card must not show', () {
      expect(
        NexMarkdownText.plain('# Plan\n\n**do** the `thing` [now](https://a.b)'),
        'Plan\n\ndo the thing now',
      );
    });

    test('leaves an underscore inside a word alone', () {
      // The reason the `_` pass follows CommonMark's intraword rule: a
      // stripper that ate these would damage text nobody ever formatted.
      expect(
        NexMarkdownText.plain('see flutter_test_config.dart'),
        'see flutter_test_config.dart',
      );
      expect(NexMarkdownText.plain('a _real_ one'), 'a real one');
    });

    test('leaves a lone marker in prose alone', () {
      expect(NexMarkdownText.plain('2 * 3 = 6'), '2 * 3 = 6');
    });

    test('drops quote markers', () {
      expect(NexMarkdownText.plain('> quoted\nplain'), 'quoted\nplain');
    });
  });

  group('nexLooksLikeMarkdown', () {
    test('says yes to structure worth rendering', () {
      expect(nexLooksLikeMarkdown('# Heading'), isTrue);
      expect(nexLooksLikeMarkdown('- one\n- two'), isTrue);
      expect(nexLooksLikeMarkdown('1. one\n2. two'), isTrue);
      expect(nexLooksLikeMarkdown('some **bold** text'), isTrue);
      expect(nexLooksLikeMarkdown('run `flutter test` first'), isTrue);
      expect(nexLooksLikeMarkdown('```dart\nfinal x = 1;\n```'), isTrue);
      expect(nexLooksLikeMarkdown('> quoted'), isTrue);
      expect(nexLooksLikeMarkdown('| a | b |\n|---|---|'), isTrue);
      expect(nexLooksLikeMarkdown('see [the docs](https://x.dev)'), isTrue);
      expect(nexLooksLikeMarkdown('- مورد اول\n- مورد دوم'), isTrue);
    });

    test('says no to ordinary prose', () {
      expect(nexLooksLikeMarkdown(''), isFalse);
      expect(nexLooksLikeMarkdown('   '), isFalse);
      expect(nexLooksLikeMarkdown('Just a sentence.'), isFalse);
      // The case that would cost something if it were wrong: an asterisk or an
      // underscore loose in prose is not markup, and rendering it as markup
      // would delete a character the user typed.
      expect(nexLooksLikeMarkdown('2 * 3 = 6'), isFalse);
      expect(nexLooksLikeMarkdown('the file is my_notes.txt'), isFalse);
      expect(nexLooksLikeMarkdown('یک جملهٔ فارسی ساده.'), isFalse);
      // A dash used as punctuation mid-line, not as a list marker.
      expect(nexLooksLikeMarkdown('سلام - حالت خوبه؟'), isFalse);
    });
  });
}
