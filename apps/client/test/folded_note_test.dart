import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';
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
  testWidgets('long pasted HTML copies exactly across paragraphs', (
    tester,
  ) async {
    final source =
        '\uFEFF<!-- first -->\r\n<!-- second -->\r\n<!DOCTYPE html>\r\n'
        '<html>\r\n<body>\r\n'
        '${'<p>A paragraph with Persian and Latin: نکس and Nex.</p>\r\n' * 200}'
        '<p>Last paragraph.</p>\r\n</body>\r\n</html>';
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: FoldedNote(text: source)),
        ),
      ),
    );
    final code = find.byType(NexCodeText);
    expect(tester.widget<NexCodeText>(code).code.length, lessThan(901));
    expect(find.textContaining('Last paragraph.'), findsNothing);
    await tester.ensureVisible(find.text('More'));
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(code, findsOneWidget);
    expect(tester.widget<NexCodeText>(code).code, source);
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    tester
        .widget<SelectionArea>(find.byType(SelectionArea))
        .focusNode!
        .requestFocus();
    region.selectAll();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(copied, source);
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
