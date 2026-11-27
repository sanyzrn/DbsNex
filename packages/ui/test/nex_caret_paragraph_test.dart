import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// The paragraph a caret is in, as a range as well as a direction.
///
/// The field caches this answer while the caret stays inside it, so the bounds
/// are part of the contract: a selection dragged inside one paragraph must not
/// re-read the whole note. The old rule found the paragraph by building the
/// start of every paragraph first, which made each keystroke in a long note
/// cost the note's length.
void main() {
  group('the caret paragraph', () {
    // «سلام\nhello\n123\nدوباره» — a note that alternates languages, with a
    // neutral paragraph in the middle.
    const text = 'سلام\nhello\n123\nدوباره';

    test('is bounded by the newlines around the caret', () {
      expect(nexCaretParagraphOf(text, 2), (
        start: 0,
        end: 4,
        direction: TextDirection.rtl,
      ));
      expect(nexCaretParagraphOf(text, 5), (
        start: 5,
        end: 10,
        direction: TextDirection.ltr,
      ));
      expect(nexCaretParagraphOf(text, 11), (
        start: 11,
        end: 14,
        direction: TextDirection.ltr,
      ), reason: 'the neutral paragraph takes the direction above it');
      expect(nexCaretParagraphOf(text, 20), (
        start: 15,
        end: 21,
        direction: TextDirection.rtl,
      ));
    });

    test('a caret on a newline belongs to the paragraph it ends', () {
      expect(nexCaretParagraphOf(text, 4), (
        start: 0,
        end: 4,
        direction: TextDirection.rtl,
      ));
      expect(nexCaretParagraphOf(text, 10), (
        start: 5,
        end: 10,
        direction: TextDirection.ltr,
      ));
    });

    test(
      'a paragraph with no strong letter falls back through its workers',
      () {
        // Only neutrals before and after: no answer at all, so the field keeps
        // the interface's direction.
        expect(nexCaretParagraphOf('123\n456\n!', 6), (
          start: 4,
          end: 7,
          direction: null,
        ));
        expect(nexCaretParagraphOf('', 0), (start: 0, end: 0, direction: null));
        expect(nexCaretParagraphOf('\n', 0), (
          start: 0,
          end: 0,
          direction: null,
        ));
        // Nothing above, so the paragraph below answers.
        expect(
          nexCaretParagraphOf('123\nسلام', 1).direction,
          TextDirection.rtl,
        );
      },
    );

    test('a carriage return is neutral, not a new paragraph', () {
      // Notes pasted from Windows carry \r\n. The paragraph still ends at
      // the \\n, and the \\r neither decides the direction nor splits it.
      expect(nexCaretParagraphOf('hello\r\nسلام', 3), (
        start: 0,
        end: 6,
        direction: TextDirection.ltr,
      ));
      expect(
        nexCaretParagraphOf('hello\r\nسلام', 9).direction,
        TextDirection.rtl,
      );
    });

    test('an out-of-range caret is clamped to the nearest paragraph', () {
      expect(nexCaretParagraphOf(text, -5).start, 0);
      expect(nexCaretParagraphOf(text, 999).start, 15);
    });
  });

  group('right-to-left scripts outside the Arabic and Hebrew blocks', () {
    test('are right to left', () {
      // Each of these used to answer "no direction", so a note opening in it
      // was laid out in the interface language instead of its own.
      const rightToLeft = <String>[
        '\u{1E900}', // Adlam
        '\u{10E80}', // Yezidi
        '\u{10900}', // Phoenician
        '\u{10840}', // Imperial Aramaic
        '\u{10A60}', // Old South Arabian
        '\u{10B40}', // Inscriptional Parthian
        '\u{10C80}', // Old Hungarian
        '\u{1E800}', // Mende Kikakui
        '\u{1EE00}', // Arabic mathematical alphabetic symbols
      ];
      for (final rune in rightToLeft) {
        expect(
          nexDirectionOf(rune),
          TextDirection.rtl,
          reason: 'U+${rune.runes.first.toRadixString(16)} was not seen',
        );
      }
    });

    test('their left-to-right neighbours are not swept in', () {
      // The supplementary planes hold both. Cypriot, Linear B and Deseret
      // are left to right and must not turn a line around; a blank answer
      // lets the first real letter decide, which is what happens here.
      const leftToRightFirst = <String>[
        '\u{10800}hello', // Cypriot
        '\u{10000}hello', // Linear B
        '\u{10400}hello', // Deseret
      ];
      for (final text in leftToRightFirst) {
        expect(
          nexDirectionOf(text),
          TextDirection.ltr,
          reason: 'a left-to-right script was read as right to left: $text',
        );
      }
    });
  });
}
