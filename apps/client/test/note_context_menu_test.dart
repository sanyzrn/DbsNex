import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/hold_menu.dart';
import 'package:nex_client/widgets/note_context_menu.dart';

/// The note's hold menu, which a tap outside must only close.
///
/// It was Flutter's stock menu, which closes on an outside tap and then lets
/// that tap carry on to whatever is underneath — opening another note, or
/// pressing a button — where the date heading's menu does nothing but close.
void main() {
  testWidgets('a tap outside the hold menu only closes it', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              NoteContextMenu(
                entries: [
                  NoteMenuEntry(NexHoldAction.copy, () {}),
                  NoteMenuEntry(NexHoldAction.delete, () {}),
                ],
                child: const SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Center(child: Text('A note')),
                ),
              ),
              const SizedBox(height: 400),
              TextButton(
                onPressed: () => pressed++,
                child: const Text('Something else'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.longPress(find.text('A note'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    // Every item carries an icon now, Delete included.
    expect(
      find.descendant(
        of: find.widgetWithText(MenuItemButton, 'Delete'),
        matching: find.byIcon(Icons.delete_outline),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Something else'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    expect(pressed, 0);

    await tester.tap(find.text('Something else'));
    await tester.pumpAndSettle();
    expect(pressed, 1);
  });
}
