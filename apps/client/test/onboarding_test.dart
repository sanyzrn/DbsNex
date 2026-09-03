import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/onboarding_screen.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/first_run_tour.dart';

import 'support/in_process_db.dart';

/// The one test file that does *not* mark onboarding done in setUp — every
/// other one does, because an empty preference store is a first-ever launch.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  Future<NexServices> testServices(Directory tmp) async {
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    return NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_onboarding_');
    services = await testServices(tmp);
    preferences = await NexPreferences.load();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Taps through the pages of prose to the step that asks for something.
  ///
  /// Counted rather than hard-coded: this used to be `for (i < 4)` in three
  /// places, so every page added to onboarding broke three tests that had
  /// nothing to do with it.
  Future<void> reachSetup(WidgetTester tester) async {
    for (var guard = 0; guard < 12; guard++) {
      if (find.text('A few quick choices').evaluate().isNotEmpty) return;
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    fail('never reached the setup step');
  }

  testWidgets('a first launch opens on onboarding, not the timeline', (
    tester,
  ) async {
    expect(preferences.onboardingComplete, isFalse);
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(TimelineScreen), findsNothing);
  });

  testWidgets('an install that has run before never sees onboarding', (
    tester,
  ) async {
    // The migration's whole job: any preference at all means this app has been
    // used, and nobody with a library gets introduced to it. The device id is
    // written by bootstrap on every launch after the first, so it stands in
    // for "not a fresh install" here.
    SharedPreferences.setMockInitialValues({'nex.device_id': 'abc'});
    final existing = await NexPreferences.load();

    expect(existing.onboardingComplete, isTrue);
  });

  testWidgets('finishing without a name is allowed and stores nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await reachSetup(tester);
    expect(find.text('A few quick choices'), findsOneWidget);

    // A name is no longer demanded. Finishing without one goes straight
    // through, and nothing is written on the user's behalf.
    await tester.tap(find.text('Start using Nex'));
    await tester.pumpAndSettle();

    expect(preferences.displayName, isNull);
    expect(preferences.onboardingComplete, isTrue);
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('a name typed on the last page is saved through', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await reachSetup(tester);
    await tester.enterText(find.byType(TextField).first, 'Saeed');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start using Nex'));
    await tester.pumpAndSettle();

    expect(preferences.displayName, 'Saeed');
    expect(preferences.onboardingComplete, isTrue);
    // Swapped, not stacked: there is nothing behind the timeline to go back to.
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('Skip skips, and lands somewhere you can write', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Skip used to jump to the one page it could not leave, which made the
    // word untrue. Every choice on that page is in Settings under the same
    // labels, so there is nothing here worth holding a fresh install for.
    expect(preferences.onboardingComplete, isTrue);
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    // Nothing was invented on the user's behalf on the way past.
    expect(preferences.displayName, anyOf(isNull, isEmpty));
  });

  testWidgets('a fresh install is not toured before it has a note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Two tutorials back to back was the complaint: five pages of prose and
    // then four stops of overlay, before anywhere to write. The timeline is
    // empty, so the tour has nothing to point at and does not open.
    expect(find.byType(FirstRunTour), findsNothing);
    expect(preferences.tourComplete, isFalse);

    // It is still owed, and falls due once there is a note to talk about.
    await services.captureText('the first thing I wrote');
    await services.refreshTimeline();
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunTour), findsOneWidget);
  });

  testWidgets('the setup page applies each choice as it is made', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await reachSetup(tester);

    // The theme and the language take effect under the user as they pick,
    // rather than waiting for the last button — picking Persian and only
    // finding out on the next screen that it took would be a worse way to ask.
    expect(preferences.themeMode, ThemeMode.system);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(preferences.themeMode, ThemeMode.dark);

    await tester.tap(find.text('فارسی'));
    await tester.pumpAndSettle();
    expect(preferences.locale?.languageCode, 'fa');

    // The AI's language is asked for separately from the app's, and answering
    // one must not answer the other.
    expect(preferences.aiOutputLanguage, AiOutputLanguage.auto);
    await tester.tap(find.text('انگلیسی'));
    await tester.pumpAndSettle();
    expect(preferences.aiOutputLanguage, AiOutputLanguage.english);
    expect(preferences.locale?.languageCode, 'fa');
  });
}
