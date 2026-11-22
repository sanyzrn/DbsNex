import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';

import 'support/nex_harness.dart';

/// Reported symptom: on a phone set to three-button navigation, the bottom of
/// a sheet ran under the navigation bar; on the same phone using gesture
/// navigation it looked right.
///
/// `showModalBottomSheet(useSafeArea: true)` reads as if it covers this and
/// does not — Flutter applies `SafeArea(bottom: false)` for that flag, and its
/// own documentation says the sheet "extends all the way to the bottom of the
/// screen, including any system intrusions". Gesture navigation reserves so
/// little that the overlap passes for padding; three buttons reserve about
/// 48dp, and the sheet's last control lands underneath them.
void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  /// What Android reports for a three-button navigation bar.
  const navBar = 48.0;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_sheet_inset_',
      onboarded: false,
    );
    services = harness.services;
    preferences = harness.preferences;
    preferences = await NexPreferences.load();
    await preferences.setLocale('en');
    // Every one of these tests starts from an empty preference store, which
    // is exactly what a first-ever launch looks like — so without this they
    // would all open on the onboarding screen instead of the timeline.
    // Onboarding has its own test file.
    await preferences.completeOnboarding();
    await preferences.completeTour();
  });

  tearDown(() => harness.dispose());

  testWidgets('a sheet ends above a three-button navigation bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);
    addTearDown(tester.view.reset);

    await services.captureText('a note to open');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('a note to open'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteDetailSheet), findsOneWidget);

    // The labelled toolbar replaced the old icon strip. Its last control
    // must clear system navigation, as must the bottom of its More menu.
    final more = tester.getRect(find.byTooltip('More actions'));
    expect(
      more.bottom,
      lessThanOrEqualTo(900 - navBar),
      reason: "the detail toolbar must end above the navigation bar",
    );

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    final delete = tester.getRect(find.text('Delete').last);
    expect(
      delete.bottom,
      lessThan(more.top),
      reason: 'the More menu opens above its toolbar',
    );
  });

  testWidgets('an outside tap only closes the More menu', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await services.captureText('a note to open');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('a note to open'));
    await tester.pumpAndSettle();
    final more = find.byTooltip('More actions');
    final edit = find.byTooltip('Edit');
    final editPosition = tester.getCenter(edit);
    final fields = find.byType(TextField).evaluate().length;
    for (final outside in [
      tester.getCenter(more),
      editPosition,
      const Offset(200, 40),
    ]) {
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      await tester.tapAt(outside);
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);
      expect(find.byType(NoteDetailSheet), findsOneWidget);
      expect(edit.hitTestable(), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(fields));
    }
  });

  testWidgets('the More menu fits above the RTL toolbar on a short screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 440);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: navBar);
    tester.view.padding = const FakeViewPadding(top: 28, bottom: navBar);
    addTearDown(tester.view.reset);

    final note = (await services.captureText('یادداشت نمونه'))!;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteDetailSheet(
            services: services,
            preferences: preferences,
            noteId: note.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NoteDetailSheet)),
    );
    final more = find.byTooltip(l10n.moreActions);
    final anchor = tester.getRect(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final last = find.ancestor(
      of: find.text(l10n.delete),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    );
    final scroll = find.ancestor(
      of: last,
      matching: find.byType(SingleChildScrollView),
    );
    final menu = tester.getRect(scroll);
    expect(menu.left, closeTo(anchor.left, 1));
    expect(menu.top, greaterThanOrEqualTo(28));
    expect(menu.bottom, lessThan(anchor.top));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
  });
}
