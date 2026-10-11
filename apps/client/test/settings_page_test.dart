import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/settings_sheet.dart';

import 'support/nex_harness.dart';

/// Settings is a page, like Tools and the library: it opens over the
/// timeline, its categories open pages of their own, and back walks out of
/// them one at a time.
void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_settings_dismiss_',
      onboarded: false,
    );
    services = harness.services;
    preferences = harness.preferences;
    preferences = await NexPreferences.load();
    // Every one of these tests starts from an empty preference store, which
    // is exactly what a first-ever launch looks like — so without this they
    // would all open on the onboarding screen instead of the timeline.
    // Onboarding has its own test file.
    await preferences.completeOnboarding();
    await preferences.completeTour();
  });

  tearDown(() => harness.dispose());

  testWidgets('a category opens its own page, and back returns', (
    tester,
  ) async {
    // Categories used to fold open in place, and remembered which were open.
    // Each now has its own page: the front page stays one line per category.
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final about = find.byKey(const ValueKey('settings-category-about'));
    await tester.ensureVisible(about);
    await tester.pumpAndSettle();
    expect(find.text('Check for updates automatically'), findsNothing);
    await tester.tap(about);
    await tester.pumpAndSettle();
    expect(find.text('Check automatically'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Check automatically'), findsNothing);
    expect(about, findsOneWidget);
  });

  testWidgets('Settings opens as a page, and back returns to the timeline', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsOneWidget);
    // A page has a way back, where the sheet had a close button.
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
