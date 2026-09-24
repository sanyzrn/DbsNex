import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  group(
    'a field runs in the direction of what is typed into it',
    _autoDirection,
  );

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
            child: NexBodyText('$english\n$persian', maxLines: 2),
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

  testWidgets('a clamped block shows no more lines than it was given', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: NexBodyText('one\ntwo\nthree\nfour', maxLines: 2),
          ),
        ),
      ),
    );

    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    // The budget is spent in the note's own lines now rather than in wrapped
    // rows, which is what keeps a two-line card two lines tall.
    expect(find.text('three'), findsNothing);
    expect(find.text('four'), findsNothing);
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
}
