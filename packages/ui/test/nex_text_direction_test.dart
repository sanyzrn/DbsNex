import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  group('direction is decided by the first strong character', () {
    test('and never changes as more of the other script arrives', () {
      // The reported bug: a note begun in English swung right — English line
      // included — at some unannounced keystroke, because the old rule counted
      // characters and flipped once Persian passed a ratio. Every one of these
      // is the same note being typed, one word at a time.
      const growing = [
        'English text',
        'English text\nمتن',
        'English text\nمتن فارسی',
        'English text\nمتن فارسی طولانی‌تر از خط اول انگلیسی',
        'English text\nمتن فارسی طولانی‌تر از خط اول انگلیسی و باز هم بیشتر',
      ];
      for (final text in growing) {
        expect(
          nexDirectionOf(text),
          TextDirection.ltr,
          reason: 'direction moved while the note was being written: $text',
        );
      }
    });

    test('a note begun in Persian stays right-to-left', () {
      expect(nexDirectionOf('متن'), TextDirection.rtl);
      expect(
        nexDirectionOf('متن فارسی\nEnglish text that is far longer'),
        TextDirection.rtl,
      );
    });

    test('what comes before the first letter does not decide', () {
      // Digits, punctuation, spaces and emoji carry no direction of their own,
      // so they are skipped rather than counted as left-to-right.
      expect(nexDirectionOf('12:30 — متن'), TextDirection.rtl);
      expect(nexDirectionOf('  "English"'), TextDirection.ltr);
      expect(nexDirectionOf('🙂 متن'), TextDirection.rtl);
    });

    test('text with no letters at all keeps the ambient direction', () {
      for (final neutral in ['', '   ', '12:30', '...', '🙂']) {
        expect(nexDirectionOf(neutral), isNull, reason: neutral);
      }
      expect(nexDirectionOf(null), isNull);
    });
  });

  testWidgets('explicit lines choose their own direction and alignment', (
    tester,
  ) async {
    const english = '[Verse - softly]';
    const persian = 'این یک خط فارسی است';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: NexBodyText('$english\n$persian')),
        ),
      ),
    );

    final englishText = tester.widget<Text>(find.text(english));
    final persianText = tester.widget<Text>(find.text(persian));
    expect(englishText.textDirection, TextDirection.ltr);
    expect(englishText.textAlign, TextAlign.left);
    expect(persianText.textDirection, TextDirection.rtl);
    expect(persianText.textAlign, TextAlign.right);
    expect(tester.getRect(find.text(english)).left, 0);
    expect(tester.getRect(find.text(persian)).right, 400);
  });
}
