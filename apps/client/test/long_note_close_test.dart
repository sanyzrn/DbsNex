import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/nex_dialog.dart';

import 'support/nex_harness.dart';

/// A long note is read to its last line, and then it has to close. The text
/// scrolls, so the handle is the one part that does not — and it used to sit
/// right under the status bar, where pulling it opened the notification shade.
void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_long_note_close_',
      onboarded: true,
    );
    services = harness.services;
    preferences = harness.preferences;
  });

  tearDown(() => harness.dispose());

  testWidgets('from the end of a long note, the handle closes it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final text = [
      'A long note',
      for (var i = 0; i < 120; i++) 'Line $i of something worth keeping.',
    ].join('\n');
    final note = (await tester.runAsync(() => services.captureText(text)))!;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              padding: const EdgeInsets.only(top: 32),
              viewPadding: const EdgeInsets.only(top: 32),
            ),
            child: Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => nexShowSheet<void>(
                    context: context,
                    builder: (_) => NoteDetailSheet(
                      services: services,
                      preferences: preferences,
                      noteId: note.id,
                      initialNote: note,
                    ),
                  ),
                  child: const Text('timeline'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('timeline'));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final handle = find.byKey(const ValueKey('nex-sheet-handle'));
    expect(handle, findsOneWidget);

    // Clear of the status bar's pull-down zone with room to spare: the
    // content stops at its share of the screen, and the handle sits on top.
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final top = tester.getTopLeft(handle).dy;
    expect(top, greaterThan(32 * 3));
    expect(
      top,
      greaterThanOrEqualTo(screen.height * (1 - nexNoteSheetMaxHeight) - 23),
    );

    // Read to the end.
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -6000),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('timeline'), findsOneWidget);

    // And close from there, by the handle.
    await tester.drag(handle, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(handle, findsNothing);
  });
}
