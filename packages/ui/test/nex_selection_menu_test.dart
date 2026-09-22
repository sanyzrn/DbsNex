import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// Whose commands are on the menu over a selection.
///
/// The rule was written once, in the client's formatting menu, and so held
/// for exactly the two fields that had a menu of their own. Everything else
/// took Flutter's default one — which is how eight other apps' names came
/// back onto the menu the moment text you only read became selectable. These
/// tests hold the rule where every surface can reach it.
void main() {
  ContextMenuButtonItem item(ContextMenuButtonType type, [String? label]) =>
      ContextMenuButtonItem(onPressed: () {}, type: type, label: label);

  test('the entries other apps put there are dropped', () {
    final kept = nexOwnMenuItems([
      item(ContextMenuButtonType.copy),
      item(ContextMenuButtonType.custom, 'Ask Copilot'),
      item(ContextMenuButtonType.selectAll),
      item(ContextMenuButtonType.custom, 'Ask ChatGPT'),
      item(ContextMenuButtonType.share),
    ]);
    expect(kept.map((i) => i.type), [
      ContextMenuButtonType.copy,
      ContextMenuButtonType.selectAll,
      ContextMenuButtonType.share,
    ]);
  });

  test('a menu of nothing but the platform survives whole', () {
    // The filter is on the type Android's text processors are given, not on
    // a list of names — so a command Flutter adds next is kept without this
    // having to hear about it.
    final own = [
      item(ContextMenuButtonType.cut),
      item(ContextMenuButtonType.paste),
      item(ContextMenuButtonType.liveTextInput),
    ];
    expect(nexOwnMenuItems(own), hasLength(3));
  });

  testWidgets('a selectable paragraph carries the app menu', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NexBodyText('a note', selectable: true)),
      ),
    );
    final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
    expect(area.contextMenuBuilder, nexSelectionMenu);
  });

  testWidgets('so does rendered markdown', (tester) async {
    // `NexMarkdown` used to reach selection by handing `selectable: true` to
    // the markdown body, which is a `SelectableText` underneath: Flutter's
    // menu, and no taps left for the links and code spans in the same
    // paragraph. It brings its own area now.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NexMarkdown('a **note**')),
      ),
    );
    final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
    expect(area.contextMenuBuilder, nexSelectionMenu);
  });

  testWidgets('a caller that owns the area is not given a second one', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NexMarkdown('a **note**', selectable: false)),
      ),
    );
    expect(find.byType(SelectionArea), findsNothing);
  });
}
