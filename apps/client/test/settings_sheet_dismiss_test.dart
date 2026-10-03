import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/settings_sheet.dart';

import 'support/nex_harness.dart';

/// Reported symptom: a fast fling starting from the bottom of Settings could
/// cross the whole scroll range and bounce past the top in one motion — the
/// same ballistic overshoot the existing dismiss-on-overscroll relies on to
/// detect a genuine downward drag at the top — closing the sheet on the way
/// there instead of merely scrolling it. A real drag once it has actually
/// arrived at the top must still close it.
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

  /// Dispatches a synthetic [OverscrollNotification] through the settings
  /// sheet's real scroll view, the same one the widget's own
  /// `NotificationListener` reacts to — this is what lets the two scenarios
  /// below be deterministic instead of depending on a scroll physics
  /// simulation to overshoot by the right amount at the right moment.
  void dispatchOverscroll(WidgetTester tester, {required bool fromDrag}) {
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    final position = scrollable.position;
    OverscrollNotification(
      metrics: position.copyWith(),
      context: scrollable.context,
      overscroll: -20,
      dragDetails: fromDrag
          ? DragUpdateDetails(globalPosition: Offset.zero)
          : null,
    ).dispatch(scrollable.context);
  }

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

  testWidgets('a fling settling past the top does not close Settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsOneWidget);

    // dragDetails: null — a ballistic simulation settling past the
    // boundary, not a finger on the glass.
    dispatchOverscroll(tester, fromDrag: false);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSheet), findsOneWidget);
  });

  testWidgets('a real drag past the top closes Settings', (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsOneWidget);

    dispatchOverscroll(tester, fromDrag: true);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSheet), findsNothing);
  });
}
