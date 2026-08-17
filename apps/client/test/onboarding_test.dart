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

  testWidgets('the last page will not finish without a name', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // Four pages of prose, then the one that asks for something.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('A few quick choices'), findsOneWidget);

    // Nothing typed: the button refuses, says why, and stays put.
    await tester.tap(find.text('Start using Nex'));
    await tester.pumpAndSettle();
    expect(find.text('Nex needs something to call you.'), findsOneWidget);
    expect(preferences.onboardingComplete, isFalse);
    expect(find.byType(TimelineScreen), findsNothing);

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

  testWidgets('Skip jumps to the setup page, it does not skip setup', (
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

    // Skip means "I have read enough", not "do not ask me": the name is
    // required either way, so it lands on the last page rather than finishing.
    expect(find.text('A few quick choices'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    expect(preferences.onboardingComplete, isFalse);
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
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

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
