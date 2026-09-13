import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// The recap stopped being a paragraph and became a short list of the things
/// waiting on somebody. Models asked for a list mostly send one — and
/// sometimes send a numbered list, a heading, a bullet, or eight lines when
/// they were asked for three.
///
/// Asking the prompt to be obeyed every time by every model, including the
/// small ones running on the phone, is a wish. This is the arithmetic.
void main() {
  group('nexTidyBrief', () {
    test('lines survive, which is the whole point', () {
      // The word clamp this replaced collapsed every run of whitespace in a
      // reply — newlines included — and handed back the paragraph the prompt
      // had just asked it not to write.
      const reply = '⏰ Call the plumber, overdue by two days.\n'
          '📋 Shopping: bread and milk still on the list.';
      expect(nexTidyBrief(reply), reply);
    });

    test('bullets and numbering come off', () {
      expect(
        nexTidyBrief('- one\n* two\n3. three\n4) four'),
        'one\ntwo\nthree\nfour',
      );
    });

    test('a heading is not one of the things', () {
      expect(nexTidyBrief('Today:\n⏰ the plumber'), '⏰ the plumber');
      expect(nexTidyBrief('## Due soon\n⏰ the plumber'), '⏰ the plumber');
      expect(nexTidyBrief('**Today**\n⏰ the plumber'), '⏰ the plumber');
    });

    test('a line that happens to be emphasised is still a line', () {
      // Some models bold everything they write. Treating that as a label
      // would throw away the briefing and keep its heading.
      expect(
        nexTidyBrief('**Call the plumber before Friday**'),
        'Call the plumber before Friday',
      );
    });

    test('a colon inside a sentence is not a heading', () {
      // "Due soon:" labels what follows it. "Shopping: bread and milk" is the
      // thing itself, and the difference is whether anything comes after.
      const line = '📋 Shopping: bread and milk still on the list';
      expect(nexTidyBrief(line), line);
      const persian = '📋 خرید: سه قلم مانده';
      expect(nexTidyBrief(persian), persian);
    });

    test('more lines than asked for are cut', () {
      final many = List.generate(9, (i) => 'thing $i').join('\n');
      expect(nexTidyBrief(many, maxLines: 3)!.split('\n'), hasLength(3));
    });

    test('a long line is cut, and prefers to stop at a sentence', () {
      final words = List.generate(40, (i) => 'w$i').join(' ');
      final cut = nexTidyBrief(words, maxWords: 10)!;
      // Ten words, the last of them carrying the ellipsis.
      expect(cut.split(' '), hasLength(10));
      expect(cut, endsWith('…'));

      // A sentence ending past halfway is a better place to stop than an
      // ellipsis is. Before halfway it is not — throwing away most of a line
      // to avoid one ellipsis is a worse line.
      expect(
        nexTidyBrief('One two three four five. Six seven eight.', maxWords: 6),
        'One two three four five.',
      );
      expect(
        nexTidyBrief('One. Two three four five six.', maxWords: 4),
        'One. Two three four…',
      );
    });

    test('blank and decorative lines are dropped, not counted', () {
      expect(nexTidyBrief('⏰ real\n\n---\n\n📋 also real'), '⏰ real\n📋 also real');
    });

    test('nothing usable is the same as no answer', () {
      expect(nexTidyBrief(null), isNull);
      expect(nexTidyBrief('   '), isNull);
      expect(nexTidyBrief('###\n---\n**'), isNull);
    });

    test('one thing waiting is one line, not a padded three', () {
      expect(nexTidyBrief('⏰ Only this'), '⏰ Only this');
    });
  });

  group('nexBriefLines', () {
    test('says as much as there is to say about, and no more', () {
      // A card that fills the same four lines every morning is a card people
      // stop reading.
      expect(nexBriefLines(1), 2);
      expect(nexBriefLines(20), 4);
    });

    test('more to say about is never less room to say it', () {
      for (var i = 1; i < 40; i++) {
        expect(
          nexBriefLines(i + 1),
          greaterThanOrEqualTo(nexBriefLines(i)),
        );
      }
    });
  });
}
