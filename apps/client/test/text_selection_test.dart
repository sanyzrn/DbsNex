import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/note_editor_sheet.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Why selecting text used to fight back.
///
/// Two separate mistakes, both about what a rebuild is allowed to do to a
/// gesture already in progress, and the editor carries both shapes — so it is
/// where they are held.
void main() {
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
  });

  Future<void> open(WidgetTester tester, {required String initial}) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  await NoteEditorSheet.show(
                    context,
                    initial: initial,
                    preferences: preferences,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets('the formatting menu survives a rebuild', (tester) async {
    // `EditableText` compares this builder by identity, and a fresh closure
    // per build reads as a changed menu — which it answers by disposing the
    // selection overlay and making a new one after the next frame. The
    // handles and their recognizers live in that overlay, so a rebuild in the
    // middle of a handle drag cancelled the drag and nothing resumed.
    await open(tester, initial: 'the boiler is making a noise');
    final before = field(tester);

    await tester.enterText(find.byType(TextField), 'the boiler is quiet now');
    await tester.pump();
    final after = field(tester);

    expect(
      identical(before, after),
      isFalse,
      reason: 'the rebuild this is about has to actually happen',
    );
    expect(
      identical(before.contextMenuBuilder, after.contextMenuBuilder),
      isTrue,
      reason: 'the menu builder changed identity across a rebuild',
    );
  });

  testWidgets('moving the caret rebuilds nothing', (tester) async {
    // A `TextEditingController` notifies when the selection moves as well as
    // when the text does, and dragging a handle is a stream of selection
    // changes. A listener that rebuilds on every notification rebuilds the
    // field underneath the drag, frame after frame.
    await open(tester, initial: 'the boiler is making a noise');
    final before = field(tester);

    before.controller!.selection = const TextSelection(
      baseOffset: 4,
      extentOffset: 10,
    );
    await tester.pump();

    expect(
      identical(before, field(tester)),
      isTrue,
      reason: 'a selection change rebuilt the field',
    );
  });
}
