import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/capture_sheet.dart';

import 'support/nex_harness.dart';

/// The capture sheet's emptiness edge: the first character of a note can be
/// a stray space, and a box of nothing but spaces is the empty box — no
/// card survives closing over it.
/// The capture sheet's one field — the timeline has a search field too.
final _field = find.descendant(
  of: find.byType(CaptureSheet),
  matching: find.byType(TextField),
);

void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_whitespace_',
      onboarded: false,
    );
    services = harness.services;
    preferences = harness.preferences;
    preferences = await NexPreferences.load();
    await preferences.setLocale('en');
    await preferences.completeOnboarding();
    await preferences.completeTour();
  });

  tearDown(() => harness.dispose());

  Future<void> openComposer(WidgetTester tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
  }

  testWidgets('a note of nothing but spaces leaves no card behind', (
    tester,
  ) async {
    await openComposer(tester);
    // A space is a character, so the note exists from the first keystroke
    // like any other (ADR-002)…
    await tester.enterText(_field, '   ');
    await tester.pumpAndSettle();
    // …and closing the sheet — back, the same route a swipe takes — is the
    // settle that must take it back out: the spaces are the empty text,
    // not a note.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await services.timeline(limit: 5), isEmpty);
  });
}
