import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_client/screens/timeline/timeline_model.dart';
import 'package:nex_client/widgets/reminder_wheel.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// 2.8.4: "Remove the note when done". A one-time reminder that, once
/// answered — Done in the shade, or its card opened and closed after it
/// rang — takes its note to Recently deleted, with an Undo that brings it
/// back as an ordinary note.
void main() {
  late NexTestHarness h;
  final past = DateTime.now().toUtc().subtract(const Duration(minutes: 5));

  setUp(() async => h = await NexTestHarness.create(name: 'nex_clears_'));
  tearDown(() => h.dispose());

  Future<Note> noteWith({required DateTime at, bool clears = true}) async {
    final note = (await h.services.captureText('buy stamps'))!;
    await h.services.setDueAt(note.id, at, clears: clears);
    return (await h.services.getById(note.id))!;
  }

  test('Done in the shade sends it to Recently deleted, once', () async {
    final note = await noteWith(at: past);
    await h.services.ring(note.id);
    await h.services.acknowledgeRinging(note.id);
    // In Recently deleted: no longer a live note.
    expect(await h.services.getById(note.id), isNull);
    expect(h.services.reminderCleared.value, [note.id]);
  });

  test('Done pressed while Nex was away is settled at the next look', () async {
    final note = await noteWith(at: past);
    await NexReminderActions.requeueAcknowledged([note.id]);
    // The hand-off is read only where notifications exist.
    NexReminders.debugSupported = true;
    addTearDown(() => NexReminders.debugSupported = null);
    await h.services.settleReminderAcks();
    expect(await h.services.getById(note.id), isNull);
    expect(h.services.reminderCleared.value, [note.id]);
  });

  test('closing the card counts only after it rang, and only with the '
      'choice made', () async {
    final ahead = await noteWith(
      at: DateTime.now().toUtc().add(const Duration(hours: 2)),
    );
    final plain = await noteWith(at: past, clears: false);
    expect(await h.services.clearAnswered(ahead.id), isFalse);
    expect(await h.services.clearAnswered(plain.id), isFalse);
    final due = await noteWith(at: past);
    expect(await h.services.clearAnswered(due.id), isTrue);
    expect(await h.services.getById(due.id), isNull);
    // Already in Recently deleted: nothing more happens to it.
    expect(await h.services.clearAnswered(due.id), isFalse);
  });

  test('Undo brings it back as an ordinary note', () async {
    final note = await noteWith(at: past);
    await h.services.clearAnswered(note.id);
    await h.services.keepCleared([note.id]);
    final back = (await h.services.getById(note.id))!;
    expect(back.deletedAt, isNull);
    expect(back.dueAt, isNull);
    expect(back.dueClears, isFalse);
    expect(await h.services.clearAnswered(note.id), isFalse);
  });

  test(
    'a spent "remove when done" reminder keeps its time until answered',
    () async {
      final note = await noteWith(at: past);
      final model = TimelineModel(
        services: h.services,
        preferences: h.preferences,
      );
      addTearDown(model.dispose);
      await model.load();
      await model.retireSpentReminders();
      expect((await h.services.getById(note.id))!.dueAt, isNotNull);
    },
  );

  for (final locale in ['en', 'fa']) {
    testWidgets('the sheet offers the choice for a one-time reminder only '
        '($locale)', (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReminderWheel(
                note: null,
                now: DateTime(2026, 11, 17, 10),
                onSubmit: (_, _) {},
                onClearsChanged: changes.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chip = find.byKey(const ValueKey('reminder-clears'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(tester.takeException(), isNull);
    });
  }
}
