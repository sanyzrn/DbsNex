import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

Offset wordPoint(WidgetTester tester, String word) {
  final text = find
      .byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(word),
      )
      .first;
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final start = paragraph.text.toPlainText().indexOf(word);
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
        '${markdown ? 'formatted' : 'plain'} selection clears outside in ${rtl ? 'FA' : 'EN'}, Copy still works',
        (tester) async {
          final selections = <SelectedContent?>[];
          final opened = <String>[];
          final word = rtl ? 'یادداشت' : 'ordinary';
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          var outsideTaps = 0;
          final source =
              '$word ${rtl ? 'متن' : 'words'} ${markdown ? '[website](https://x.dev)' : 'https://x.dev'}';
          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.only(top: 100),
                    child: Column(
                      children: [
                        NexSelectionArea(
                          onSelectionChanged: selections.add,
                          child: markdown
                              ? NexMarkdown(
                                  source,
                                  selectable: false,
                                  onTapLink: opened.add,
                                  onHoldLink: (_, _) {},
                                )
                              : NexLinkText(
                                  source,
                                  selectable: false,
                                  onTapLink: opened.add,
                                ),
                        ),
                        GestureDetector(
                          key: const ValueKey('outside'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => outsideTaps++,
                          child: const SizedBox(width: 400, height: 200),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.longPressAt(wordPoint(tester, word));
          await tester.pumpAndSettle();
          expect(selections.last?.plainText, word);
          await tester.tap(find.byKey(const ValueKey('outside')));
          await tester.pumpAndSettle();
          expect(selections.last?.plainText ?? '', isEmpty);
          expect(find.text('Copy'), findsNothing);
          expect(
            outsideTaps,
            1,
            reason: 'deselecting must not consume the outside action',
          );
          await tester.longPressAt(wordPoint(tester, word));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Copy'));
          await tester.pumpAndSettle();
          expect(
            copied,
            word,
            reason: 'the floating toolbar is inside the selection tap group',
          );
          await tester.tapAt(
            wordPoint(tester, markdown ? 'website' : 'https://x.dev'),
          );
          await tester.pumpAndSettle();
          expect(opened, ['https://x.dev']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
