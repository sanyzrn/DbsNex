import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/screens/onboarding_screen.dart';
import 'package:nex_client/screens/timeline_screen.dart';

import 'support/nex_harness.dart';

/// The shared harness (W4.3) itself: what every other test now stands on.
void main() {
  testWidgets('pumpNexApp opens on the timeline of an empty library', (
    tester,
  ) async {
    final harness = await pumpNexApp(tester);
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(await harness.db.timeline(), isEmpty);
  });

  testWidgets('a harness that has not onboarded shows onboarding', (
    tester,
  ) async {
    await pumpNexApp(tester, onboarded: false);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  test(
    'dispose closes the library and removes it, and is safe twice',
    () async {
      final harness = await NexTestHarness.create();
      expect(harness.root.existsSync(), isTrue);
      await harness.dispose();
      expect(harness.root.existsSync(), isFalse);
      await harness.dispose();
    },
  );

  test('seeded preferences reach the services', () async {
    final harness = await NexTestHarness.create(
      preferences: {'appearance.solar_calendar': true},
    );
    addTearDown(harness.dispose);
    expect(harness.services.solarCalendar, isTrue);
  });

  test(
    'Persian gets the solar calendar until it is turned off (LOC-11)',
    () async {
      final fa = await NexTestHarness.create(
        preferences: {'appearance.locale': 'fa'},
      );
      addTearDown(fa.dispose);
      expect(fa.preferences.solarCalendar, isTrue);

      final chosen = await NexTestHarness.create(
        preferences: {
          'appearance.locale': 'fa',
          'appearance.solar_calendar': false,
        },
      );
      addTearDown(chosen.dispose);
      expect(chosen.preferences.solarCalendar, isFalse);

      final en = await NexTestHarness.create(
        preferences: {'appearance.locale': 'en'},
      );
      addTearDown(en.dispose);
      expect(en.preferences.solarCalendar, isFalse);
    },
  );
}
