import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/folded_note.dart';
import 'package:nex_client/platform/hold_menu.dart';
import 'package:nex_client/widgets/note_context_menu.dart';
import 'package:nex_client/l10n/app_localizations.dart';

void main() {
  testWidgets('long notes reveal the rest without changing the source', (
    tester,
  ) async {
    final text = '${'Intro paragraph. ' * 70}\nEND OF NOTE';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: FoldedNote(text: text)),
        ),
      ),
    );
    expect(find.textContaining('END OF NOTE'), findsNothing);
    await tester.ensureVisible(find.text('More'));
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(find.textContaining('END OF NOTE'), findsWidgets);
    await tester.ensureVisible(find.text('Less'));
    await tester.tap(find.text('Less'));
    await tester.pump();
    expect(find.textContaining('END OF NOTE'), findsNothing);
  });
  testWidgets('touch hold opens the useful note actions', (tester) async {
    var pinned = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteContextMenu(
            entries: [
              NoteMenuEntry(NexHoldAction.pin, () => pinned = true),
              NoteMenuEntry(NexHoldAction.copy, () {}),
              NoteMenuEntry(NexHoldAction.edit, () {}),
              NoteMenuEntry(NexHoldAction.remind, () {}),
              NoteMenuEntry(NexHoldAction.delete, () {}),
            ],
            child: const SizedBox(
              width: 300,
              height: 100,
              child: Text('Hold this note'),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('Hold this note'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    expect(pinned, isTrue);
  });
}
