import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/nex_dialog.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// A tapped card opens its note the way the assistant opens: the ordinary
/// sheet rising from the bottom, at the assistant's own softer pace
/// ([nexSheetRise]). Until 1.92 the sheet grew out of the card instead.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_card_opening_');
    await harness.services.captureText('the card that opens');
    await harness.services.refreshTimeline();
  });

  tearDown(() => harness.dispose());

  testWidgets('closing a note without editing does not reload the timeline', (
    tester,
  ) async {
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NoteCard).first);
    await tester.pumpAndSettle();
    final reads = harness.db.timelineReads;

    Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
    await tester.pumpAndSettle();

    expect(harness.db.timelineReads, reads);
    expect(find.byType(NoteCard), findsWidgets);
  });

  testWidgets('an unseen note edit still refreshes the timeline on close', (
    tester,
  ) async {
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    final note = (await harness.services.timeline()).first;
    await tester.tap(find.byType(NoteCard).first);
    await tester.pumpAndSettle();
    final reads = harness.db.timelineReads;
    // Simulate an edit that persisted but did not dispatch a timeline event,
    // as some detail-sheet metadata actions do.
    await harness.db.updateNote(note.id, 'updated behind the detail sheet');

    Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
    await tester.pumpAndSettle();

    expect(harness.db.timelineReads, reads + 1);
    expect(find.text('updated behind the detail sheet'), findsOneWidget);
  });

  testWidgets("the note rises from the bottom at the assistant's pace", (
    tester,
  ) async {
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NoteCard).first);
    await tester.pump();
    // Halfway through the rise the sheet is still on its way up: the
    // default slide would long since have arrived.
    await tester.pump(nexSheetRise.duration! * 0.4);
    final sheet = find.byType(NoteDetailSheet);
    expect(sheet, findsOneWidget);
    final rising = tester.getTopLeft(sheet).dy;

    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(sheet).dy;
    expect(rising, greaterThan(settled + 1));
    // Only the note itself: no copy of the card held over it.
    expect(
      find.byWidgetPredicate((w) => w is NoteCard && w.onTap == null),
      findsNothing,
    );
  });
}
