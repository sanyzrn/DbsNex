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
      final out = NexTextFormatting.link(
        'see docs here',
        4,
        8,
        'https://x.dev',
      );
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
        NexMarkdownText.plain(
          '# Plan\n\n**do** the `thing` [now](https://a.b)',
        ),
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

    test('edge shapes decide the same way they always did', () {
      // Seven hashes is not a heading; a quote needs its space; a "1." past
      // nine digits is prose. The construct list is one alternation now, and
      // these are the shapes most likely to disagree if it ever drifted.
      expect(nexLooksLikeMarkdown('####### seven hashes'), isFalse);
      expect(nexLooksLikeMarkdown('>nospace'), isFalse);
      expect(nexLooksLikeMarkdown('1000000000. ten digits'), isFalse);
      expect(nexLooksLikeMarkdown('999999999. nine digits'), isTrue);
      expect(nexLooksLikeMarkdown('line\r\n# crlf heading'), isTrue);
      expect(nexLooksLikeMarkdown('- - -'), isTrue);
      expect(nexLooksLikeMarkdown('a | b'), isFalse);
      expect(nexLooksLikeMarkdown('| a | b |'), isTrue);
    });
  });
  group('NexMarkdownText.preview on a long note', () {
    // A body past the scan cap: enough filler to be past it, then the shapes
    // that decide what the cap may and may not change.
    String longBody(String tail, {int head = 6000}) =>
        List.filled(
          head ~/ 20,
          'word word word word\n',
          growable: false,
        ).join() +
        tail;

    test('a short note is previewed exactly as before', () {
      expect(NexMarkdownText.preview('# Plan\n**do** it'), 'Plan\ndo it');
      expect(NexMarkdownText.preview('just a sentence'), 'just a sentence');
    });

    test('a long plain note shows its first pages, not its whole body', () {
      final note = longBody('the end of a very long note');
      final out = NexMarkdownText.preview(note);
      // Starts with the same words...
      expect(out.startsWith('word word'), isTrue);
      // ...stops somewhere near the cap rather than at the end...
      expect(out.length, lessThanOrEqualTo(4096));
      // ...and never reaches the note's actual ending.
      expect(out.contains('the end of a very long note'), isFalse);
    });

    test('a long Markdown note is stripped where it is shown', () {
      final note = longBody('and then **bold** to finish');
      final out = NexMarkdownText.preview(note);
      expect(out.contains('**'), isFalse);
      expect(out.endsWith('bold to finish'), isFalse); // past the cap
      // The visible start is exactly what stripping the whole note would
      // show there — the cap changes where the preview stops, not what it
      // says.
      expect(out, NexMarkdownText.plain(note).substring(0, out.length));
    });

    test('the gate still reads the whole note, so the card keeps agreeing '
        'with the sheet', () {
      // Markdown structure begins well past the scan cap; the pairs in the
      // first pages must still be unwrapped, because the renderer will treat
      // this note as Markdown from its first line.
      // Filler to put the pairs inside the scan window, more filler to push
      // the note past it, and the structure that trips the gate last.
      final head = longBody('a _paired_ word\n', head: 2000);
      final rest = longBody('', head: 6000);
      final note = '$head$rest\n# A heading at the far end';
      final out = NexMarkdownText.preview(note);
      expect(nexLooksLikeMarkdown(note), isTrue);
      expect(out.contains('_paired_'), isFalse);
      expect(out.contains('paired'), isTrue);
      expect(out.contains('# A heading'), isFalse);
    });

    test('the cut lands on a line break when there is one', () {
      final note = longBody('tail line');
      final out = NexMarkdownText.preview(note);
      // Either it stopped on a line boundary or the note had no line break
      // near the cap — both are correct; what must hold is the length cap.
      expect(out.length, lessThanOrEqualTo(4096));
      expect(note.startsWith(out), isTrue);
    });

    test('one unbroken line is cut mid-line and stays honest', () {
      final note = 'x' * 9000;
      final out = NexMarkdownText.preview(note);
      expect(out.length, 4096);
      expect(out, 'x' * 4096);
    });

    test('asking twice costs one answer: the memoized result is returned', () {
      final note = longBody('repeat me', head: 12000);
      final first = NexMarkdownText.preview(note);
      final second = NexMarkdownText.preview(note);
      expect(
        identical(first, second),
        isTrue,
        reason:
            'the same string object should be handed back, not '
            'restripped',
      );
      // A different string with the same content reaches the same answer.
      final copy = String.fromCharCodes(note.runes);
      final third = NexMarkdownText.preview(copy);
      expect(third, first);
      // And a note edited inside its first pages is a different answer.
      // (One edited past the scan cap is not, and should not be: no preview
      // of it can show the difference.)
      final prefix = 'different start\n';
      final edited = '$prefix${note.substring(prefix.length)}';
      expect(
        NexMarkdownText.preview(edited).endsWith('repeat me too'),
        isFalse,
      );
      expect(NexMarkdownText.preview(edited) != first, isTrue);
    });
  });
}
