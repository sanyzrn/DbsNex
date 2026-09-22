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
