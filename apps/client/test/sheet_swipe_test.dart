import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/dismiss_on_overscroll.dart';
import 'package:nex_client/widgets/nex_dialog.dart';

/// Every shared sheet closes when its content is pulled down past the top —
/// a long one too, whose list would otherwise take the drag — and only the
/// sheet closes, even where a sheet still carries its own listener.
void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    bool ownListener = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => nexShowSheet<void>(
                  context: context,
                  builder: (_) {
                    final list = ListView(
                      key: const ValueKey('sheet-list'),
                      shrinkWrap: true,
                      children: [
                        for (var i = 0; i < 60; i++)
                          ListTile(title: Text('Row $i')),
                      ],
                    );
                    return ownListener
                        ? NexDismissOnOverscroll(child: list)
                        : list;
                  },
                ),
                child: const Text('page underneath'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('page underneath'));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsOneWidget);
  }

  Future<void> pullDown(WidgetTester tester) async {
    await tester.drag(find.text('Row 2'), const Offset(0, 300));
    await tester.pumpAndSettle();
  }

  testWidgets('a long sheet closes when pulled down from its content', (
    tester,
  ) async {
    await openSheet(tester);
    await pullDown(tester);
    expect(find.text('Row 0'), findsNothing);
    expect(find.text('page underneath'), findsOneWidget);
  });

  testWidgets('a sheet with its own listener closes once, not twice', (
    tester,
  ) async {
    await openSheet(tester, ownListener: true);
    await pullDown(tester);
    expect(find.text('Row 0'), findsNothing);
    expect(find.text('page underneath'), findsOneWidget);
  });

  // A box that scrolls inside the sheet's own scroll view — an AI result, a
  // translation — overscrolls at its own top too, and that is not a request
  // to close anything: reading a long transcript to its first line and
  // pulling a little further used to take the whole sheet with it, position
  // and all. The note detail sheet's own shape: a capped box in the scroll.
  testWidgets('overscroll inside a nested box does not close the sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => nexShowSheet<void>(
                  context: context,
                  builder: (_) => ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 700),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: NexDismissOnOverscroll(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 240,
                                    ),
                                    child: SingleChildScrollView(
                                      primary: false,
                                      child: Column(
                                        children: [
                                          for (var i = 0; i < 30; i++)
                                            ListTile(title: Text('Nested $i')),
                                        ],
                                      ),
                                    ),
                                  ),
                                  for (var i = 0; i < 60; i++)
                                    ListTile(title: Text('Row $i')),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('page underneath'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('page underneath'));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsOneWidget);

    // The nested box starts at its own top: a downward pull over it
    // overscrolls the box (a depth the sheet never asked about), not the
    // sheet's own scroll.
    await tester.drag(find.text('Nested 2'), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsOneWidget, reason: 'the sheet stays');

    // The same drag over the sheet's own scroll, pinned at its top, still
    // closes it.
    await tester.drag(find.text('Row 2'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsNothing);
    expect(find.text('page underneath'), findsOneWidget);
  });

  test('no new raw bottom sheet: they go through nexShowSheet', () {
    // The few that predate the rule, each with its own reason. A sheet
    // added anywhere else uses nexShowSheet, and with it the glass surface,
    // the handle, the safe area and pull-down-to-close — see
    // docs/16-design-language.md.
    const allowed = {
      // The shared wrapper itself.
      'lib/widgets/nex_dialog.dart',
      // The assistant: a full-height surface of its own with its own glow.
      'lib/widgets/ai_chat_sheet.dart',
      'lib/widgets/ai_chat/chat_panels.dart',
      // Short action lists sized to their rows.
      'lib/screens/note_detail/detail_frame.dart',
      'lib/widgets/commitments_sheet.dart',
    };
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !allowed.contains(file.path.replaceAll(r'\', '/')) &&
            RegExp(r'\bshowModalBottomSheet\s*<|\bshowModalBottomSheet\s*\(')
                .hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'Open sheets with nexShowSheet (lib/widgets/nex_dialog.dart).',
    );
  });
}
