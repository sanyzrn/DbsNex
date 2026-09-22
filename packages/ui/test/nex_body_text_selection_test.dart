import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// Whether a paragraph can be taken hold of.
///
/// A `Text` answers no gesture at all — not a long press, not a double tap,
/// no handles — and Nex renders almost everything a person *reads* through
/// [NexBodyText]. From the outside that is indistinguishable from selection
/// being broken, which is exactly how it was reported.
void main() {
  Future<void> show(
    WidgetTester tester, {
    required bool selectable,
    String text = 'the boiler is making a noise',
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NexBodyText(text, selectable: selectable),
      ),
    ),
  );

  testWidgets('a reading surface can be selected from', (tester) async {
    await show(tester, selectable: true);
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('a card preview cannot', (tester) async {
    // The default, and it has to stay the default: a timeline card lives
    // inside a swipe recognizer and a tap that opens the note, and a long
    // press that starts selecting a preview is a long press that did not open
    // the thing it was on.
    await show(tester, selectable: false);
    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('a Persian paragraph owns the direction around it', (
    tester,
  ) async {
    // The handles, the magnifier and the menu over a selection are built
    // against the *ambient* direction, not the `textDirection` argument. With
    // only the argument, a Persian paragraph in an English interface got a
    // right-to-left block under a left-to-right overlay: the two handles came
    // up on the wrong ends, and dragging one widened the selection from the
    // wrong side. The fields were given this in v1.13.0; read-only text was
    // not selectable then, so it never needed it.
    const persian = 'این یک جملهٔ فارسی است';
    await show(tester, selectable: true, text: persian);
    expect(
      Directionality.of(tester.element(find.text(persian))),
      TextDirection.rtl,
    );
  });

  testWidgets('lines that agree are one paragraph', (tester) async {
    // A column of separate lines is a column of separate selectables, and a
    // handle dragged down through it has to be handed from one to the next —
    // which is the stuttering that made selecting a Persian note feel like
    // work. Lines only need separating when they disagree about direction.
    const note = 'خط اول این یادداشت\nخط دوم همین یادداشت';
    await show(tester, selectable: true, text: note);
    expect(find.text(note), findsOneWidget);
  });

  testWidgets('lines that disagree still get their own direction', (
    tester,
  ) async {
    const english = 'a line in English';
    const persian = 'یک خط فارسی';
    await show(tester, selectable: true, text: '$english\n$persian');
    expect(find.text('$english\n$persian'), findsNothing);
    expect(
      Directionality.of(tester.element(find.text(persian))),
      TextDirection.rtl,
    );
    expect(
      Directionality.of(tester.element(find.text(english))),
      TextDirection.ltr,
    );
  });

  testWidgets('selection does not change how the lines are laid out', (
    tester,
  ) async {
    // Per-line direction is the other half of this widget and the half that
    // was hard to get right. Wrapping it in an area must not disturb it: a
    // note that opens in English still lays its Persian lines out on the
    // right.
    const mixed = 'English first\nمتن فارسی';
    await show(tester, selectable: true, text: mixed);
    final persian = tester.widget<Text>(find.text('متن فارسی'));
    expect(persian.textDirection, TextDirection.rtl);
    final english = tester.widget<Text>(find.text('English first'));
    expect(english.textDirection, TextDirection.ltr);
  });
}
