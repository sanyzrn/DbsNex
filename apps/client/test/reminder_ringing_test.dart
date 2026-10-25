import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_core/nex_core.dart';
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
    final n1 = (await h.db.captureText('one'))!;
    final n2 = (await h.db.captureText('two'))!;
    await h.services.ring(n1.id);
    await h.services.ring(n2.id);
    await h.services.acknowledgeRinging(n1.id);
    expect(h.services.ringing.value, {n2.id});
    await h.services.syncRinging();
    expect(h.services.ringing.value, {n2.id});
  });

  test('only notes ring: an id with no note behind it is let go', () async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final note = (await h.db.captureText('kept'))!;
    await h.services.ring(note.id);
    await h.services.ring('a-recurring-item');
    await h.services.syncRinging();
    expect(h.services.ringing.value, {note.id});
  });

  test('a repeating reminder offers Done alone; a one-time one, both', () {
    List<String> ids({required bool repeating}) => [
      for (final action in NexReminderActions.noteDetails(
        body: null,
        secret: false,
        repeating: repeating,
      ).android!.actions!)
        action.id,
    ];
    expect(ids(repeating: false), [
      NexReminderActions.done,
      NexReminderActions.snooze,
    ]);
    expect(ids(repeating: true), [NexReminderActions.done]);
    expect(
      [
        for (final action in NexReminderActions.commitmentDetails(
          secret: false,
        ).android!.actions!)
          action.id,
      ],
      [NexReminderActions.done],
    );
  });

  test(
    'Done on a recurring item meets it at the moment it was pressed',
    () async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      final due = DateTime.now().subtract(const Duration(hours: 2));
      await h.services.saveCommitment(
        NexCommitment(
          id: 'water',
          title: 'water the plants',
          cadence: NexCadence.days,
          every: 3,
          dueAt: due,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      final answered = await NexReminderActions.handle(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: NexReminderActions.done,
          payload: '${NexReminderActions.commitmentPrefix}water',
        ),
        FlutterLocalNotificationsPlugin(),
      );
      expect(answered, '${NexReminderActions.commitmentPrefix}water');
      // Not a note: no bell is stopped for it.
      expect(await NexReminderActions.takeAcknowledged(), isEmpty);

      expect(await h.services.applyMetFromShade(), 1);
      final met = (await h.services.commitments()).single;
      expect(met.lastMetAt, isNotNull);
      expect(met.dueAt.isAfter(DateTime.now()), isTrue);
      // Read once: a second look moves nothing on again.
      expect(await h.services.applyMetFromShade(), 0);
    },
  );
}
