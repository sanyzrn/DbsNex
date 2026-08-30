import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/in_process_db.dart';

/// A one-off reminder that has rung gets exactly one more showing.
///
/// Reported three times and fixed twice, with no test either time — which is
/// how it kept coming back. The rule is narrow enough to write down: a
/// reminder still ahead keeps its chip; one that has rung keeps it until the
/// reader has been shown it once and put the app away; a repeating one never
/// lapses at all. What "put the app away" means is the part that was wrong
/// before, because no route is pushed when someone simply leaves.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  Future<NexServices> build(Directory dir) async {
    final dbPath = p.join(dir.path, 'nex.sqlite');
    final mediaDir = p.join(dir.path, 'media');
    final backupDir = p.join(dir.path, 'backups');
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
    tmp = Directory.systemTemp.createTempSync('nex_reminder_chip_');
    services = await build(tmp);
    preferences = await NexPreferences.load();
    await preferences.completeOnboarding();
    await preferences.completeTour();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Sends the app to the background the way the OS does, which is the whole
  /// point: `didPushNext` never fires for someone who just leaves.
  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
  }

  testWidgets('a rung reminder stops showing after the app is put away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final note = (await services.captureText('call the plumber'))!;
    await services.setDueAt(
      note.id,
      DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    );
    await services.refreshTimeline();

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // It rang two hours ago and this is the first sight of it since.
    expect(preferences.seenReminders, isEmpty);

    await background(tester);

    // Leaving is what counts as having seen it — no route was pushed.
    expect(
      preferences.seenReminders,
      contains(note.id),
      reason: 'backgrounding the app did not mark the rung reminder seen',
    );
  });

  testWidgets('and stays gone across a restart', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final note = (await services.captureText('call the plumber'))!;
    await services.setDueAt(
      note.id,
      DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    );
    await services.refreshTimeline();

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await background(tester);

    // The report is that it comes back — so the record has to survive a cold
    // launch, not just the session that wrote it.
    final relaunched = await NexPreferences.load();
    expect(relaunched.seenReminders, contains(note.id));
  });

  testWidgets('a reminder still ahead keeps its chip', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final note = (await services.captureText('the dentist, on Thursday'))!;
    await services.setDueAt(
      note.id,
      DateTime.now().toUtc().add(const Duration(days: 2)),
    );
    await services.refreshTimeline();

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await background(tester);

    // Nothing has rung, so nothing has been seen. Marking it here would take
    // the chip off a reminder that has not happened yet.
    expect(preferences.seenReminders, isNot(contains(note.id)));
  });

  testWidgets('a repeating reminder is never spent', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final note = (await services.captureText('take the tablets'))!;
    await services.setDueAt(
      note.id,
      DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      repeat: NoteRepeat.daily,
    );
    await services.refreshTimeline();

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await background(tester);

    // Its stored time is in the past by design after the first firing, and it
    // is still going to ring again.
    expect(preferences.seenReminders, isNot(contains(note.id)));
  });
}
