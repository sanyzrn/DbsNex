import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// A card is a picture of a note. Once a note's body can carry formatting, a
/// card that prints the markers is a picture of the source instead.
void main() {
  Note textNote(String body) => Note(
    id: 'n1',
    type: NoteType.text,
    content: body,
    createdAt: DateTime.utc(2026, 7, 28),
    updatedAt: DateTime.utc(2026, 7, 28),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  Widget host(Note note) => MaterialApp(
    theme: nexLightTheme(),
    home: Scaffold(body: SizedBox(width: 400, child: NoteCard(note: note))),
  );

  testWidgets('a formatted note shows its words, not its markers', (
    tester,
  ) async {
    await tester.pumpWidget(host(textNote('the **urgent** one')));
    await tester.pumpAndSettle();

    expect(find.text('the urgent one'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('an unformatted note is left exactly as it was typed', (
    tester,
  ) async {
    // The case that costs something if the stripper runs unconditionally:
    // both of these would lose characters the writer put there on purpose.
    await tester.pumpWidget(host(textNote('2 * 3 * 4')));
    await tester.pumpAndSettle();
    expect(find.text('2 * 3 * 4'), findsOneWidget);

    await tester.pumpWidget(host(textNote('see flutter_test_config.dart')));
    await tester.pumpAndSettle();
    expect(find.text('see flutter_test_config.dart'), findsOneWidget);
  });

  testWidgets('a screen reader hears the words too', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(textNote('the **urgent** one')));
    await tester.pumpAndSettle();

    // "asterisk asterisk urgent asterisk asterisk" is the audible version of
    // a card showing its own source.
    expect(
      find.bySemanticsLabel(RegExp(r'the urgent one')),
      findsAtLeastNWidgets(1),
    );
    handle.dispose();
  });
}
