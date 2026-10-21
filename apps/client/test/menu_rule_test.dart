import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// Every menu in the app is the card's hold menu: the same width, corners,
/// surface and padding, an icon on every action line, red for what destroys.
/// One place makes that so (`NexPopupMenuButton` and `nexMenuItem` in
/// packages/ui), and this keeps the next menu from being drawn some other way
/// — which is how the thread and tag menus came to be smaller, plainer and
/// without icons than the card's own.
void main() {
  test('no bare PopupMenuItem, PopupMenuButton or showMenu in the app', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            RegExp(
              r'(?<![A-Za-z_.])(PopupMenuItem|PopupMenuButton|CheckedPopupMenuItem|showMenu)\s*[<(]',
            ).hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Use NexPopupMenuButton with nexMenuItem (or nexShowContextMenu); '
          'see docs/16-design-language.md, Menus.',
    );
  });

  testWidgets('a page menu looks like the card menu: icon, width, corners', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              NexPopupMenuButton<String>(
                key: const ValueKey('menu'),
                itemBuilder: (_) => [
                  nexMenuItem(
                    value: 'edit',
                    icon: Icons.edit_outlined,
                    label: 'Rename',
                  ),
                  nexMenuItem(
                    value: 'delete',
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('menu')));
    await tester.pumpAndSettle();

    // An icon on every action line.
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    // At least the shared width, however short the words.
    final rename = tester.getSize(
      find.ancestor(of: find.text('Rename'), matching: find.byType(InkWell)),
    );
    expect(rename.width, greaterThanOrEqualTo(180));
    expect(rename.height, greaterThanOrEqualTo(48));
    // The card menu's corners and raised surface: the menu's own Material.
    final surface = tester
        .widgetList<Material>(find.byType(Material))
        .firstWhere(
          (m) => m.shape is RoundedRectangleBorder && m.elevation == 3,
        );
    expect(
      (surface.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(NexRadius.lg),
    );
  });
}
