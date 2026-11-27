import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  group(
    'a field runs in the direction of what is typed into it',
    _autoDirection,
  );

  group('the direction of the paragraph the caret is in', () {
    test('is the paragraph\'s own, whichever paragraph that is', () {
      // The ADR-037 case, at editing time: a note with an English line under
      // a Persian one. The field cannot lay both paragraphs out in their own
      // directions at once, so it lays out around the one being written in —
      // and only that one.
      const text = 'سلام\nhello\nدوباره';
      expect(nexCaretDirectionOf(text, 0), TextDirection.rtl);
      expect(nexCaretDirectionOf(text, 4), TextDirection.rtl);
      expect(nexCaretDirectionOf(text, 5), TextDirection.ltr);
      expect(nexCaretDirectionOf(text, 10), TextDirection.ltr);
      expect(nexCaretDirectionOf(text, 11), TextDirection.rtl);
      expect(nexCaretDirectionOf(text, 17), TextDirection.rtl);
    });

    test('a caret on a newline ends the paragraph before it', () {
      // A caret sitting on a newline is the end of that paragraph — the
      // person pressed Enter there, or dragged to its end — not the start of
      // the one after it.
      const text = 'سلام\n123\nhello';
      expect(nexCaretDirectionOf(text, 4), TextDirection.rtl);
      // And one just past that newline is the start of the next paragraph.
      expect(
        nexCaretDirectionOf(text, 5),
        TextDirection.rtl,
        reason: 'a neutral paragraph follows the one above it',
      );
      expect(
        nexCaretDirectionOf(text, 9),
        TextDirection.ltr,
        reason: 'the paragraph after the neutral one',
      );
    });

    test('a paragraph with no direction of its own follows its neighbours', () {
      // An empty paragraph, or one of digits, keeps the side the writing was
      // on — which is what keeps a new paragraph from flipping the field the
      // moment Enter is pressed.
      expect(nexCaretDirectionOf('سلام\n', 5), TextDirection.rtl);
      expect(nexCaretDirectionOf('سلام\n123\n', 10), TextDirection.rtl);
      expect(nexCaretDirectionOf('hello\n123\n', 11), TextDirection.ltr);
      // And with nothing before it, the paragraph after it answers.
      expect(nexCaretDirectionOf('123\nسلام', 2), TextDirection.rtl);
      // Only when no paragraph carries any direction is the answer none.
      expect(nexCaretDirectionOf('123\n456\n!', 14), isNull);
      expect(nexCaretDirectionOf('', 0), isNull);
    });

    test('an out-of-range caret resolves as the nearest position', () {
      expect(nexCaretDirectionOf('hello\nسلام', -1), TextDirection.ltr);
      expect(nexCaretDirectionOf('hello\nسلام', 99), TextDirection.rtl);
    });
  });

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

    test('neutral marks inside the Arabic block are skipped', () {
      // Found by an independent audit: the Arabic block was treated as
      // strong right-to-left end to end, so text that happened to begin
      // with an Arabic comma or a harakah — pasted, usually — laid an
      // English sentence out right to left. UAX #9 classes them CS and NSM,
      // and P2 skips both.
      expect(nexDirectionOf('\u060C hello'), TextDirection.ltr);
      expect(nexDirectionOf('\u064E hello'), TextDirection.ltr);
      expect(nexDirectionOf('\u05B0 hello'), TextDirection.ltr);
      // Letters in the same block are still what they were.
      expect(nexDirectionOf('\u061B hello'), TextDirection.rtl);
    });

    test('an explicit direction mark decides', () {
      // LRM and RLM exist to answer exactly this question, and other apps
      // put them at the front of text to pin its direction. LRM was ignored
      // outright.
      expect(nexDirectionOf('\u200Eمتن'), TextDirection.ltr);
      expect(nexDirectionOf('\u200Fhello'), TextDirection.rtl);
      expect(nexDirectionOf('\u061Chello'), TextDirection.rtl);
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

    test('Persian and Arabic digits are numbers, not letters', () {
      // They live inside the Arabic block, so the strong-rtl range swept them
      // up — and this whole group's rule is *first strong character*, which
      // UAX #9 P2 defines to skip numbers. Only ASCII digits were ever tested,
      // so the gap was invisible.
      for (final digits in ['۱۲۳', '٠٩٨', '۱۴۰۳/۰۵/۱۲', '٪۲۵']) {
        expect(
          nexDirectionOf(digits),
          isNull,
          reason: '$digits is a number, and a number picks no side',
        );
      }
    });

    test('a number in front of English does not turn the line around', () {
      // The visible half. A phone number, a price or a Persian date at the
      // start of an English note flipped the whole paragraph right-to-left —
      // in the English UI, where the ambient direction was not already
      // covering for it.
      expect(nexDirectionOf('۰۹۱۲ call Ali'), TextDirection.ltr);
      expect(nexDirectionOf('۱۲۳ abc'), TextDirection.ltr);

      // And the Persian case is untouched: the digits are skipped and the
      // first letter still decides.
      expect(nexDirectionOf('۰۹۱۲ زنگ بزن'), TextDirection.rtl);
      expect(nexDirectionOf('٪۲۵ تخفیف'), TextDirection.rtl);
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
          body: SizedBox(
            width: 400,
            child: NexTextSurface('$english\n$persian'),
          ),
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

  testWidgets('a clamped block still gives each line its own direction', (
    tester,
  ) async {
    // The bug this is for: per-line direction used to apply only when nothing
    // was clamping the text, and everything that shows a *preview* of a note
    // clamps it. So one direction — the first line's — was imposed on the
    // rest, and a note that opens in English laid its Persian lines out left
    // to right. Which way round it looked wrong depended on which language
    // the note happened to open in, which is why it only happened sometimes.
    const english = 'promptpad v2';
    const persian = 'این خط باید راست‌چین باشد';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: NexTextSurface('$english\n$persian', maxLines: 2),
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text(english)).textDirection,
      TextDirection.ltr,
    );
    expect(
      tester.widget<Text>(find.text(persian)).textDirection,
      TextDirection.rtl,
      reason: 'the second line followed the first line\'s script',
    );
    expect(tester.getRect(find.text(persian)).right, 400);
  });

  testWidgets('a clamped block shows no more rows than it was given', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: NexTextSurface('one\ntwo\nthree\nfour', maxLines: 2),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    expect(paragraph.maxLines, 2);
    expect(paragraph.didExceedMaxLines, isTrue);
  });

  testWidgets('a preview reads on from its first paragraph', (tester) async {
    // Three long paragraphs in a two-row preview used to show the first row
    // of the first and the first row of the second: two half-sentences that
    // read as nonsense. The first paragraph now runs on into row two.
    final first = 'word ' * 60;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: NexTextSurface(
              '$first\n\nsecond paragraph\nthird',
              maxLines: 2,
            ),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    // Both rows are the first paragraph: the second one starts after it.
    final secondRow = paragraph.getPositionForOffset(
      Offset(1, paragraph.size.height - 2),
    );
    expect(secondRow.offset, lessThan(first.length));
    // The blank line between paragraphs is not spent as a row.
    expect(paragraph.text.toPlainText().contains('\n\n'), isFalse);
  });

  testWidgets('mixed-direction lines share the budget in reading order', (
    tester,
  ) async {
    final english = 'word ' * 60;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: NexTextSurface('$english\nیک خط فارسی', maxLines: 2),
          ),
        ),
      ),
    );
    // The long first line fills both rows; the Persian one is never drawn.
    expect(find.text('یک خط فارسی'), findsNothing);
    expect(tester.widget<Text>(find.text(english)).maxLines, 2);
  });

  testWidgets('a preview cut at a line boundary says so with an ellipsis', (
    tester,
  ) async {
    // The budget ended exactly where a line did, with more lines after it:
    // without a mark the preview reads as the note's ending rather than
    // its beginning.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: NexTextSurface('first\nدوم\nسوم', maxLines: 2),
          ),
        ),
      ),
    );
    expect(find.text('first'), findsOneWidget);
    expect(find.text('دوم\u2026'), findsOneWidget);
    expect(find.text('سوم'), findsNothing);
  });

  testWidgets('a line cut mid-sentence does not wear two ellipses', (
    tester,
  ) async {
    final english = 'word ' * 60;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: NexTextSurface('$english\nیک خط فارسی', maxLines: 2),
          ),
        ),
      ),
    );
    // The long line was clamped by the budget itself, so its own overflow
    // ellipsis is the whole of the mark — nothing is appended to it.
    expect(find.text('$english\u2026'), findsNothing);
  });

  testWidgets('blank lines are not spent from a larger mixed budget either', (
    tester,
  ) async {
    // Small budgets filtered the blanks before they got here; a four-row
    // preview used to spend a row of them on air.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: NexTextSurface('first\n\nسطر فارسی\n\nthird', maxLines: 4),
          ),
        ),
      ),
    );
    expect(find.text('\u200B'), findsNothing);
    expect(find.text('first'), findsOneWidget);
    expect(find.text('سطر فارسی'), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
  });
}

/// [NexAutoDirection] is a widget rather than a call to [nexDirectionOf]
/// because of two things a plain rebuild gets wrong. This is the record of
/// both.
void _autoDirection() {
  Widget host(
    TextEditingController controller, {
    required void Function() onBuild,
  }) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        child: NexAutoDirection(
          controller: controller,
          builder: (context, direction) {
            onBuild();
            return TextField(
              controller: controller,
              textDirection: direction,
              textAlign: TextAlign.start,
            );
          },
        ),
      ),
    ),
  );

  testWidgets('a moving selection does not rebuild the field', (tester) async {
    // The bug this is here for: a `TextEditingController` notifies its
    // listeners when the selection moves, not only when the text does. A
    // builder listening to the whole value rebuilt the field on every frame of
    // a handle drag, and a field being rebuilt underneath a selection is a
    // selection that will not be dragged.
    final controller = TextEditingController(text: 'hello there');
    addTearDown(controller.dispose);
    var builds = 0;
    await tester.pumpWidget(host(controller, onBuild: () => builds++));
    final before = builds;

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    expect(builds, before);
  });

  testWidgets('text that does not change the direction does not rebuild', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);
    var builds = 0;
    await tester.pumpWidget(host(controller, onBuild: () => builds++));
    final before = builds;
    controller.text = 'hello there';
    await tester.pump();
    expect(builds, before);
  });

  testWidgets('the direction changing does rebuild, and turns the field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, onBuild: () {}));
    // Empty: no direction of its own, so the interface's stands. That is what
    // puts the placeholder at the left edge in English.
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      isNull,
    );

    controller.text = 'متن فارسی';
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('the field gets its own Directionality, not just the argument', (
    tester,
  ) async {
    // The half that the `textDirection:` argument cannot do. Everything built
    // around the paragraph — the decoration, the hint, the selection handles
    // and the context menu — resolves against the ambient direction, so a
    // right-to-left paragraph under a left-to-right ambient gets a selection
    // overlay that disagrees with the text it is attached to.
    final controller = TextEditingController(text: 'متن فارسی');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, onBuild: () {}));
    expect(
      Directionality.of(tester.element(find.byType(TextField))),
      TextDirection.rtl,
    );
  });

  testWidgets('a field that gains a direction keeps its focus and selection', (
    tester,
  ) async {
    // Why the `Directionality` is always present rather than added once the
    // text has a direction: inserting a widget changes the shape of the tree,
    // and the element below it is rebuilt from scratch. For a focused field
    // that means losing the focus and the selection at the exact moment the
    // first letter is typed.
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, onBuild: () {}));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    expect(state.widget.focusNode.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'متن');
    await tester.pump();
    expect(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .hasFocus,
      isTrue,
      reason: 'the field lost focus when its direction stopped being null',
    );
    expect(controller.selection.isValid, isTrue);
  });

  testWidgets('the field follows the caret into the other language', (
    tester,
  ) async {
    // ADR-037, at editing time: a two-paragraph note. The field lays out
    // around the paragraph being written in, so writing in either language
    // puts that language's paragraph on its own side with its punctuation at
    // its own end.
    final controller = TextEditingController(text: 'سلام\nhello');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, onBuild: () {}));
    TextField field() => tester.widget<TextField>(find.byType(TextField));

    // The caret starts in the Persian paragraph.
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(field().textDirection, TextDirection.rtl);

    // Into the English one, and back.
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    expect(field().textDirection, TextDirection.ltr);
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    expect(field().textDirection, TextDirection.rtl);
  });

  testWidgets('turning the field keeps the editor and its selection', (
    tester,
  ) async {
    // The direction changes with the caret, which changes the layout, and
    // only the layout: the editor below must keep its element, its focus
    // and its selection through the turn.
    final controller = TextEditingController(text: 'سلام\nhello');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, onBuild: () {}));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final before = tester.state<EditableTextState>(find.byType(EditableText));

    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );
    expect(
      identical(
        before,
        tester.state<EditableTextState>(find.byType(EditableText)),
      ),
      isTrue,
      reason: 'the field was rebuilt from scratch when it turned',
    );
    expect(before.widget.focusNode.hasFocus, isTrue);
    expect(controller.selection.isValid, isTrue);
  });

  testWidgets('a caret that does not change paragraphs does not rebuild', (
    tester,
  ) async {
    // The listener watches the whole value — the selection moves constantly —
    // but a move that stays inside one paragraph keeps the direction, so
    // nothing below is rebuilt.
    final controller = TextEditingController(text: 'سلام\nhello');
    addTearDown(controller.dispose);
    var builds = 0;
    await tester.pumpWidget(host(controller, onBuild: () => builds++));
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    final before = builds;

    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    expect(builds, before);
  });

  testWidgets('a fixed direction is kept, whatever is typed', (tester) async {
    // Code is the one field that is always left to right, even with Persian
    // comments in it.
    final controller = TextEditingController(text: 'کد');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            child: NexAutoDirection(
              controller: controller,
              direction: TextDirection.ltr,
              builder: (context, direction) =>
                  TextField(controller: controller, textDirection: direction),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );
  });
}
