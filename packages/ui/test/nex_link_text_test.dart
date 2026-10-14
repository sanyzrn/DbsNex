import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

Offset linkPoint(WidgetTester tester, String label) {
  final finder = find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().contains(label),
  );
  expect(
    finder,
    findsOneWidget,
    reason: tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .join(' | '),
  );
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final start = paragraph.text.toPlainText().indexOf(label);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + 1),
      )
      .first;
  return paragraph.localToGlobal(box.toRect().center);
}

void main() {
  for (final markdown in [false, true]) {
    for (final rtl in [false, true]) {
      testWidgets(
        '${markdown ? 'Markdown' : 'plain'} links: tap, hold and scroll in ${rtl ? 'FA' : 'EN'}',
        (tester) async {
          final opened = <String>[];
          final held = <String>[];
          final selections = <SelectedContent?>[];
          final source =
              '${rtl ? 'یک یادداشت' : 'A note'}\n\n'
              '${markdown ? '[**website**](https://x.dev)' : 'https://x.dev'}\n\n'
              'https://second.dev\n\n'
              '${List.filled(30, 'more text').join('\n')}';
          await tester.pumpWidget(
            MaterialApp(
              theme: rtl ? nexDarkTheme() : nexLightTheme(),
              home: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Scaffold(
                  body: SelectionArea(
                    onSelectionChanged: selections.add,
                    child: SingleChildScrollView(
                      child: markdown
                          ? NexMarkdown(
                              source,
                              selectable: false,
                              onTapLink: opened.add,
                              onHoldLink: (href, _) => held.add(href),
                            )
                          : NexLinkText(
                              source,
                              selectable: false,
                              onTapLink: opened.add,
                              onHoldLink: (href, _) => held.add(href),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final at = linkPoint(tester, markdown ? 'website' : 'https://x.dev');
          await tester.tapAt(at);
          await tester.pumpAndSettle();
          expect(opened, ['https://x.dev']);
          opened.clear();
          await tester.longPressAt(at);
          await tester.pumpAndSettle();
          expect(held, ['https://x.dev']);
          expect(
            opened,
            isEmpty,
            reason: 'a hold must not launch the browser on release',
          );
          expect(
            selections.whereType<SelectedContent>().where(
              (s) => s.plainText.isNotEmpty,
            ),
            isEmpty,
          );
          final second = linkPoint(tester, 'https://second.dev');
          await tester.tapAt(second);
          await tester.pumpAndSettle();
          expect(opened, ['https://second.dev']);
          opened.clear();
          await tester.longPressAt(second);
          await tester.pumpAndSettle();
          expect(held, ['https://x.dev', 'https://second.dev']);
          held.clear();
          await tester.dragFrom(at, const Offset(0, -160));
          await tester.pumpAndSettle();
          expect(opened, isEmpty);
          expect(held, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('plain text keeps literal operators and every line', (
    tester,
  ) async {
    const source = '2 * 3 * 4\nhttps://x.dev\nیادداشت فارسی';
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: NexLinkText(source))),
    );
    expect(find.byType(NexMarkdown), findsNothing);
    expect(find.text('2 * 3 * 4', findRichText: true), findsOneWidget);
    expect(find.text('یادداشت فارسی', findRichText: true), findsOneWidget);
  });

  testWidgets('holding ordinary words beside a link still selects text', (
    tester,
  ) async {
    final selected = <SelectedContent?>[];
    final held = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: selected.add,
            child: NexLinkText(
              'ordinary words https://x.dev',
              selectable: false,
              onHoldLink: (href, _) => held.add(href),
            ),
          ),
        ),
      ),
    );
    await tester.longPressAt(linkPoint(tester, 'ordinary'));
    await tester.pumpAndSettle();
    expect(
      selected.whereType<SelectedContent>().any(
        (s) => s.plainText.contains('ordinary'),
      ),
      isTrue,
    );
    expect(held, isEmpty);
  });
}
