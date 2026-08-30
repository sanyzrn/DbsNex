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

/// A one-off reminder retires itself once it has rung.
///
/// Reported three times and answered twice by hiding the chip while the
/// reminder stayed on the note — so the detail sheet still offered to remove
/// it, and removing it by hand was the only way to be rid of it. The rule is
/// narrow enough to write down: a reminder still ahead is untouched; a
/// repeating one is never spent, because its stored time is in the past by
/// design after the first firing; a one-off that has rung is cleared outright
/// once the reader has been shown it and put the app away.
///
/// What "put the app away" means is the part that was wrong before: no route
/// is pushed when someone simply leaves, so the lifecycle is what has to be
/// driven here.
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

  testWidgets('a rung one-off reminder clears itself when the app is put away', (
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

    // It rang two hours ago and this is the first sight of it since, so it is
    // still on the note: one more showing is the point.
    expect((await services.getById(note.id))!.dueAt, isNotNull);

    await background(tester);

    // Leaving is what retires it — no route was pushed.
    final after = (await services.getById(note.id))!;
    expect(
      after.dueAt,
      isNull,
      reason: 'a rung one-off reminder was not cleared when the app was put away',
    );
    // The note itself is untouched; only the reminder was.
    expect(after.content, 'call the plumber');
  });

  testWidgets('and is gone from the note, not merely hidden', (tester) async {
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

    // The report is that it comes back. It cannot: the reminder is gone from
    // the note, not hidden by a record beside it that a reinstall would lose.
    expect((await services.getById(note.id))!.dueAt, isNull);
    expect((await services.getById(note.id))!.dueRepeat, NoteRepeat.once);
  });

  testWidgets('a reminder still ahead is left alone', (tester) async {
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

    // Nothing has rung. Clearing here would delete a reminder that has not
    // happened yet, which is the one thing worse than keeping a spent one.
    expect((await services.getById(note.id))!.dueAt, isNotNull);
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
    final after = (await services.getById(note.id))!;
    expect(after.dueAt, isNotNull);
    expect(after.dueRepeat, NoteRepeat.daily);
  });
}
