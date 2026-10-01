import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/nex_card_opening.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// W7.3: a tapped card opens into its note — the sheet grows out of the
/// card, and the card holds still over it until the note has taken its
/// place.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_card_opening_');
    await harness.services.captureText('the card that opens');
    await harness.services.refreshTimeline();
  });

  tearDown(() => harness.dispose());

  Finder ghostCard() =>
      find.byWidgetPredicate((w) => w is NoteCard && w.onTap == null);

  testWidgets('the card stays where it was while the sheet grows from it', (
    tester,
  ) async {
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    final card = find.byType(NoteCard).first;
    final before = tester.getRect(card);

    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(NexCardOpening), findsOneWidget);
    expect(ghostCard(), findsOneWidget);
    expect(
      tester.getRect(ghostCard()),
      before,
      reason: 'icon and title stay exactly where they were',
    );

    await tester.pumpAndSettle();
    expect(ghostCard(), findsNothing, reason: 'gone once the note is open');
    expect(find.byType(NoteDetailSheet), findsOneWidget);
    expect(find.text('the card that opens'), findsWidgets);

    // Closing is the ordinary sheet closing.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(NoteDetailSheet), findsNothing);
    expect(ghostCard(), findsNothing);
  });

  testWidgets('with animations off the sheet simply opens', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: harness.app(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NoteCard).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(ghostCard(), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(NoteDetailSheet), findsOneWidget);
  });
}
