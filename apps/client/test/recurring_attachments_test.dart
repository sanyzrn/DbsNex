import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/recurring_attachments.dart';

import 'support/nex_harness.dart';

/// The attachments gateway a Recurring item carries its linked notes in.
///
/// Delete used to close the note's sheet and do nothing: the
/// `DetailResult.deleted` the sheet answered with was dropped on the floor,
/// so the note stayed — and "delete sometimes does nothing" is the one belief
/// about an app nobody comes back from. The collections learned to act on
/// that answer (see `nexOpenNoteFromCollection`); this is the same fix here.
void main() {
  late NexTestHarness harness;
  late NexServices services;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_recurring_attach_',
      onboarded: false,
    );
    services = harness.services;
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester, List<String> noteIds) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RecurringAttachments(
            services: services,
            details: {'notes': noteIds},
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('deleting a linked note from the gateway deletes it, with Undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final note = (await services.captureText('receipt follow-up'))!;
    await open(tester, [note.id]);
    expect(find.text('receipt follow-up'), findsOneWidget);

    // The linked note's chip opens its detail sheet.
    await tester.tap(find.text('receipt follow-up'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteDetailSheet), findsOneWidget);

    // Delete lives behind the sheet's More actions, the last row there.
    await tester.tap(
      find.descendant(
        of: find.byType(NoteDetailSheet),
        matching: find.byIcon(Icons.more_horiz),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // The sheet's answer is acted on: a soft delete, and an Undo that works.
    expect(find.byType(NoteDetailSheet), findsNothing);
    expect(await services.getById(note.id), isNull);
    expect((await services.deletedNotes()).map((n) => n.id), [note.id]);
    expect(find.text('Note deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await services.getById(note.id), isNotNull);
    expect((await services.deletedNotes()), isEmpty);
  });

  testWidgets('closing the sheet without deleting leaves the note alone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final note = (await services.captureText('just looking'))!;
    await open(tester, [note.id]);

    await tester.tap(find.text('just looking'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteDetailSheet), findsOneWidget);

    // Back out of the detail sheet: a dismissal is not a delete.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(NoteDetailSheet), findsNothing);
    expect(await services.getById(note.id), isNotNull);
    expect(find.text('Note deleted'), findsNothing);
  });
}
