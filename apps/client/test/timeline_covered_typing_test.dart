import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// NEX-UI-01, end to end: a person typing into the brief's or the
/// assistant's settings screen — a route covering the home timeline — used
/// to buy one whole covered-timeline rebuild per character, because every
/// one of those writes notified the preferences and the timeline rebuilds
/// wholesale on every notify. The notify waits for the typing to pause now;
/// the typing itself rebuilds nothing.
void main() {
  testWidgets('typing behind a covering route leaves the timeline alone', (
    tester,
  ) async {
    final harness = await NexTestHarness.create(name: 'nex_covered_typing_');
    addTearDown(harness.dispose);
    await harness.services.captureText('a note to be under everything');
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    // The screen itself, not only its cards: a preferences notify rebuilds
    // the whole timeline wholesale (the rows cache absorbs the note rows —
    // the chrome is what a covered rebuild pays for).
    var screenRebuilds = 0;
    var cardRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is TimelineScreen) screenRebuilds++;
      if (element.widget is NoteCard) cardRebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // A covering route, the way the brief's and the assistant's settings
    // screens cover the home screen while their fields are typed into.
    final nav = Navigator.of(tester.element(find.byType(TimelineScreen)));
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The sentence, one saved word per frame, the way typing actually
    // happens — back-to-back writes inside a single frame would coalesce
    // into one rebuild even without any fix, and the storm this file pins
    // is the one a real keyboard produces.
    final soFar = StringBuffer();
    for (final word in ['read ', 'my ', 'notes ', 'carefully ', 'today ']) {
      soFar.write(word);
      await harness.preferences.setAiInstruction(soFar.toString().trim());
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(screenRebuilds, 0, reason: 'typing notifies nobody until it pauses');
    expect(cardRebuilds, 0);
    expect(
      harness.preferences.aiInstruction,
      'read my notes carefully today',
      reason: 'and every keystroke is saved as it happens',
    );

    // The pause arrives: one notify, one covered rebuild — not one per
    // keystroke. (The rebuild itself is the timeline's wholesale-on-notify
    // behaviour; what was removed is the storm, and a rebuild nobody can
    // see behind a covering route still keeps the screen consistent.)
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      screenRebuilds,
      lessThanOrEqualTo(1),
      reason: 'one rebuild for the whole pause, not one per keystroke',
    );
    expect(
      cardRebuilds,
      lessThanOrEqualTo(screenRebuilds),
      reason: 'the rows cache keeps the rebuild from rebuilding cards',
    );

    // Back on the timeline, it is whole and current — didPopNext's own
    // signature check is the other half of the deferral.
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(find.byType(NoteCard), findsOneWidget);
  });
}
