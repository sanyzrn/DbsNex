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

  testWidgets('category choices survive a new app tree and language change', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final about = find.byKey(const ValueKey('settings-section-about'));
    await tester.ensureVisible(about);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: about, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    expect(preferences.isSettingsSectionExpanded('about'), isTrue);
    expect(preferences.isSettingsSectionExpanded('security'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final reloaded = await NexPreferences.load();
    await reloaded.setLocale('fa');
    await tester.pumpWidget(NexApp(services: services, preferences: reloaded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(tester.widget<ExpansionTile>(about).initiallyExpanded, isTrue);
    await tester.ensureVisible(about);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: about, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    expect(
      (await NexPreferences.load()).isSettingsSectionExpanded('about'),
      isFalse,
    );
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
