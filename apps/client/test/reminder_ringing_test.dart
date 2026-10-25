import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// 2.3.0: a reminder that rang rings on its card — a bell in place of the
/// type icon — until the card is opened, and opening it answers it.
void main() {
  testWidgets('a ringing note shows a bell until its card is opened', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final note = (await h.db.captureText('Call the bank'))!;
    await h.services.refreshTimeline();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final card = find.byWidgetPredicate(
      (w) => w is NoteCard && w.note.id == note.id,
    );
    expect(tester.widget<NoteCard>(card).ringing, isFalse);

    await tester.runAsync(() => h.services.ring(note.id));
    await tester.pump();
    expect(tester.widget<NoteCard>(card).ringing, isTrue);
    expect(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.notifications_active_rounded),
      ),
      findsOneWidget,
    );
    // Survives a restart: it is kept, not just drawn.
    expect(h.preferences.ringingNotes, contains(note.id));

    await tester.tap(card);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(h.services.ringing.value, isNot(contains(note.id)));
    expect(h.preferences.ringingNotes, isNot(contains(note.id)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  test('Done pressed while the app was away stops the bell', () async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    await h.services.ring('n1');
    await h.services.ring('n2');
    await h.services.acknowledgeRinging('n1');
    expect(h.services.ringing.value, {'n2'});
    await h.services.syncRinging();
    expect(h.services.ringing.value, {'n2'});
  });
}
