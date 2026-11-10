import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/editor_drafts.dart';
import 'package:nex_client/widgets/checklist_capture_sheet.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// The sheet's own buttons, and the drafts it comes back with: the Save
/// double-tap race and the restored caret.
void main() {
  testWidgets('a double-tap on Save closes only the sheet', (tester) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    var sheetClosed = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  await Navigator.of(context).push<List<ChecklistItem>>(
                    MaterialPageRoute(
                      // A Scaffold: the pushed page carries no Material of
                      // its own, and the sheet's field and Save button both
                      // need one.
                      builder: (_) => Scaffold(
                        body: ChecklistCaptureSheet(
                          preferences: h.preferences,
                          initial: [ChecklistItem(text: 'Bread', done: false)],
                        ),
                      ),
                    ),
                  );
                  sheetClosed++;
                },
                child: const Text('underneath'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('underneath'));
    await tester.pumpAndSettle();
    // A second tap on a Save that has not visibly answered yet used to pop
    // the *underlying* route as well.
    await tester.tap(find.byType(FilledButton));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(sheetClosed, 1);
    expect(find.text('underneath'), findsOneWidget);
  });

  testWidgets('a restored draft opens with the caret at its end', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    const words = 'Bread\nMilk';
    // The harness stops short of the app's bootstrap, which is what attaches
    // the drafts store: hand the preferences one to recover from.
    final drafts = EditorDrafts(h.root.path);
    h.preferences.editorDrafts = drafts;
    drafts.write('checklist-new', {'text': words});
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChecklistCaptureSheet(preferences: h.preferences)),
      ),
    );
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, words);
    // Assigning `.text` resets the selection, which the editor reads as the
    // start of the text; the sheet now carries the caret across explicitly.
    expect(field.controller!.selection.isCollapsed, isTrue);
    expect(field.controller!.selection.baseOffset, words.length);
  });
}
