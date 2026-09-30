import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/library_screen.dart';
import 'package:nex_client/screens/recently_deleted_screen.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_client/screens/tag_manager_screen.dart';

import 'support/nex_harness.dart';

/// Settings holds preferences. Content lives somewhere a person would look for
/// content.
void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_library_',
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
    // The storage figure is measured by walking directories, which is real
    // async I/O and so never resolves inside flutter_test's fake-async zone —
    // its skeleton stays up for the whole test. A repeating shimmer means
    // `pumpAndSettle` can never settle, so this asks the platform for the
    // reduced-motion the OS itself offers; NexSkeleton honours it by stopping
    // outright.
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  });

  tearDown(() async {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
    await harness.dispose();
  });

  testWidgets('Trash and Tags are one tap from the timeline', (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);

    // A note deleted by an accidental swipe has to be recoverable without
    // reasoning your way to a gear icon.
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    expect(find.byType(RecentlyDeletedScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.byType(TagManagerScreen), findsOneWidget);
  });

  testWidgets('Settings no longer holds anything containing notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final sheet = find.byType(SettingsSheet);
    expect(sheet, findsOneWidget);
    for (final row in ['Tags', 'Trash', 'Storage']) {
      expect(
        find.descendant(of: sheet, matching: find.text(row)),
        findsNothing,
        reason: '$row is content, not a preference',
      );
    }
    // What is left is preferences, and they are still there.
    expect(
      find.descendant(of: sheet, matching: find.text('Appearance')),
      findsOneWidget,
    );
  });
}
