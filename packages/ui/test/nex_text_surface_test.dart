import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// W4.1: one surface for the user's own words, in both of its fits.
void main() {
  Widget host(Widget child, {TextDirection ui = TextDirection.ltr}) =>
      MaterialApp(
        home: Directionality(
          textDirection: ui,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  TextDirection ambientOf(WidgetTester tester, String text) =>
      Directionality.of(tester.element(find.text(text)));

  testWidgets('a Persian line in an English interface turns, handles too', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const SizedBox(width: 300, child: NexTextSurface.line('سلام دنیا'))),
    );
    final text = tester.widget<Text>(find.text('سلام دنیا'));
    expect(text.textDirection, TextDirection.rtl);
    expect(text.textAlign, TextAlign.right);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    // The ambient direction is what places selection handles and menus.
    expect(ambientOf(tester, 'سلام دنیا'), TextDirection.rtl);
  });

  testWidgets('an English line in a Persian interface stays left to right', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SizedBox(width: 300, child: NexTextSurface.line('Buy milk')),
        ui: TextDirection.rtl,
      ),
    );
    expect(ambientOf(tester, 'Buy milk'), TextDirection.ltr);
    expect(
      tester.widget<Text>(find.text('Buy milk')).textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('hugged text is as wide as its words, a block fills the row', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NexTextSurface('yes', fit: NexTextFit.hug),
              NexTextSurface('block'),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.text('yes')).width, lessThan(100));
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('block'),
                  matching: find.byType(SizedBox),
                )
                .first,
          )
          .width,
      300,
    );
  });

  testWidgets('selectable text brings a selection area, hugged or not', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            NexTextSurface('read me', selectable: true),
            NexTextSurface('and me', selectable: true, fit: NexTextFit.hug),
          ],
        ),
      ),
    );
    expect(find.byType(SelectionArea), findsNWidgets(2));
  });

  testWidgets('a line is never selectable: it lives inside a tap target', (
    tester,
  ) async {
    await tester.pumpWidget(host(const NexTextSurface.line('checklist item')));
    expect(find.byType(SelectionArea), findsNothing);
  });
}
