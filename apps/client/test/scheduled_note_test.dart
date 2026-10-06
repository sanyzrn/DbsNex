import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_client/screens/scheduled_screen.dart';
import 'package:nex_client/widgets/capture_sheet.dart';

import 'support/nex_harness.dart';

/// Hold Send to have a note arrive later. Until then it is nowhere a note
/// is; at its time it is an ordinary note.
void main() {
  Finder captureField() => find.descendant(
    of: find.byType(CaptureSheet),
    matching: find.byType(TextField),
  );
  Finder send() => find.byKey(const ValueKey('capture-send'));

  testWidgets('held Send schedules the note and takes it off the timeline', (
    tester,
  ) async {
    final harness = await pumpNexApp(tester);
    final services = harness.services;

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(captureField(), 'open me next month');
    await tester.pumpAndSettle();
    // Told about the hold, the first few times there is something to send.
    expect(find.byKey(const ValueKey('schedule-hint')), findsOneWidget);

    await tester.longPress(send());
    await tester.pumpAndSettle();
    expect(find.text('Schedule note'), findsOneWidget);
    // No repeat on a delivery.
    expect(find.text('Repeat'), findsNothing);
    await tester.tap(find.text('In a month'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Arrives'));
    await tester.pumpAndSettle();

    expect(find.byType(CaptureSheet), findsNothing);
    expect(find.text('open me next month'), findsNothing);
    expect(await services.timeline(limit: 10), isEmpty);
    final waiting = await services.scheduledNotes();
    expect(waiting.single.content, 'open me next month');
    final inDays = waiting.single.releaseAt
        .difference(DateTime.now().toUtc())
        .inDays;
    expect(inDays, inInclusiveRange(27, 31));
    expect(harness.preferences.scheduleHintDue, isFalse);

    // Delivered: an ordinary note, under the same id.
    final arrived = await services.releaseScheduledNow(waiting.single.id);
    expect(arrived!.id, waiting.single.id);
    await tester.pumpAndSettle();
    expect(find.text('open me next month'), findsOneWidget);
    expect(await services.scheduledNotes(), isEmpty);
  });

  testWidgets('a plain tap on Send still just sends', (tester) async {
    final harness = await pumpNexApp(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(captureField(), 'right now');
    await tester.pumpAndSettle();
    await tester.tap(send());
    await tester.pumpAndSettle();
    expect(find.byType(CaptureSheet), findsNothing);
    expect(
      (await harness.services.timeline(limit: 5)).single.content,
      'right now',
    );
    expect(await harness.services.scheduledNotes(), isEmpty);
  });

  testWidgets('the Scheduled page lists, delivers and discards', (
    tester,
  ) async {
    final harness = await pumpNexApp(tester);
    final services = harness.services;
    Future<String> waiting(String text, Duration from) async {
      final note = await services.captureText(text);
      await services.scheduleNote(note!.id, DateTime.now().add(from).toUtc());
      return note.id;
    }

    await waiting('later still', const Duration(days: 40));
    await waiting('soon', const Duration(days: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scheduled'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduledScreen), findsOneWidget);
    final cards = find.textContaining(RegExp('^(soon|later still)\$'));
    expect(
      tester.widgetList<Text>(cards).map((t) => t.data),
      ['soon', 'later still'],
      reason: 'the soonest first',
    );

    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deliver now'));
    await tester.pumpAndSettle();
    expect(find.text('soon'), findsNothing);
    expect((await services.timeline(limit: 5)).map((n) => n.content), ['soon']);

    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(await services.scheduledNotes(), isEmpty);
    expect(find.textContaining('Nothing scheduled'), findsOneWidget);
  });

  testWidgets('what comes due while the app is away arrives on return', (
    tester,
  ) async {
    final harness = await pumpNexApp(tester);
    final services = harness.services;
    final note = await services.captureText('due in a moment');
    await services.scheduleNote(
      note!.id,
      DateTime.now().add(const Duration(milliseconds: 300)).toUtc(),
    );
    expect(await services.releaseDueNotes(), isEmpty);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    final arrived = await services.releaseDueNotes();
    expect(arrived.single.content, 'due in a moment');
    await tester.pumpAndSettle();
    expect(find.text('due in a moment'), findsOneWidget);
  });

  test('a scheduled arrival never shares an alarm with a reminder', () {
    expect(
      NexReminders.arrivalIdFor('note-1'),
      isNot(NexReminders.idFor('note-1')),
    );
    expect(
      NexReminders.arrivalIdFor('note-1'),
      greaterThanOrEqualTo(NexReminders.reservedIds),
    );
  });
}
