import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/commitments_sheet.dart';
import 'package:nex_client/widgets/note_spotlight.dart';
import 'package:nex_ui/nex_ui.dart';

import 'package:nex_client/platform/nex_services.dart';

import 'support/nex_harness.dart';

/// A reminder tapped while Nex was closed: the app starts, and the timeline it
/// opens on has to scroll to the note and point at it where the person can
/// see it — not behind the opening animation, not before the list exists.
void main() {
  testWidgets('a cold tap on a reminder scrolls to its note and marks it', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final target = (await h.db.captureText('The oldest reminder target'))!;
    for (var i = 0; i < 225; i++) {
      await h.db.captureText('Newer note $i');
    }
    await h.services.refreshTimeline();
    // What the plugin reports when the notification started the app.
    h.services.reminders.debugLaunchNote(target.id);

    await tester.pumpWidget(h.app());
    Finder active() =>
        find.byWidgetPredicate((w) => w is NoteSpotlight && w.active);
    var frames = 0;
    for (; frames < 400 && active().evaluate().isEmpty; frames++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(active(), findsOneWidget, reason: 'after $frames frames');

    final card = find.descendant(
      of: active(),
      matching: find.byWidgetPredicate(
        (w) => w is NoteCard && w.note.id == target.id,
      ),
    );
    final rect = tester.getRect(card);
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(height));
    // Tapped, so it rings on its card until the card is opened.
    expect(h.services.ringing.value, contains(target.id));
    expect(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.notifications_active_rounded),
      ),
      findsOneWidget,
    );
    // A ringing bell never settles; stop it before settling the rest.
    h.services.ringing.value = const {};
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('under the app lock the pointing waits for the unlock', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final target = (await h.db.captureText('The oldest reminder target'))!;
    for (var i = 0; i < 60; i++) {
      await h.db.captureText('Newer note $i');
    }
    await h.services.refreshTimeline();
    h.services.reminders.debugLaunchNote(target.id);

    final locked = ValueNotifier<bool>(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ValueListenableBuilder<bool>(
          valueListenable: locked,
          builder: (_, value, _) => TimelineScreen(
            services: h.services,
            preferences: h.preferences,
            locked: value,
          ),
        ),
      ),
    );
    Finder active() =>
        find.byWidgetPredicate((w) => w is NoteSpotlight && w.active);
    // Everything that would have played behind the gate has not.
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(active(), findsNothing);

    locked.value = false;
    await tester.pump();
    var frames = 0;
    for (; frames < 400 && active().evaluate().isEmpty; frames++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(active(), findsOneWidget, reason: 'after $frames frames');
    h.services.ringing.value = const {};
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('a recurring notification opens only after unlocking, once', (
    tester,
  ) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final locked = ValueNotifier<bool>(true);
    addTearDown(locked.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ValueListenableBuilder<bool>(
          valueListenable: locked,
          builder: (_, value, _) => TimelineScreen(
            services: h.services,
            preferences: h.preferences,
            locked: value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    h.services.reminders.onOpenRecurring!();
    await tester.pumpAndSettle();
    expect(find.byType(RecurringScreen), findsNothing);
    locked.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(RecurringScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    locked.value = true;
    await tester.pump();
    locked.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(RecurringScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
