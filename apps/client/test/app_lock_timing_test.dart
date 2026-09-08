import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/in_process_db.dart';

/// When the lock closes.
///
/// It used to close the instant the app left the screen, full stop — correct,
/// and five fingerprints a minute for someone switching to a browser to copy
/// a link and coming straight back. The three timings differ only in *when*,
/// so what these check is exactly that: the same lock, at three moments.
///
/// The one thing all three share is that the answer survives the process
/// dying. Android stops a backgrounded app freely, so anything held only in
/// memory is a lock that opens itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nex/os_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late NexPreferences preferences;

  Future<NexServices> boot(Map<String, Object> extra) async {
    SharedPreferences.setMockInitialValues({
      'onboarding.complete': true,
      'onboarding.tour_complete': true,
      'security.app_lock': true,
      ...extra,
    });
    final tmp = Directory.systemTemp.createTempSync('nex_lock_timing_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    preferences = await NexPreferences.load();
    final services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: preferences,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
    addTearDown(services.dispose);
    return services;
  }

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> leave(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  }

  bool gateIsUp(WidgetTester tester) =>
      find.byKey(appLockBarrierKey).evaluate().isNotEmpty;

  testWidgets('immediately: leaving closes it', (tester) async {
    final services = await boot({'security.lock_timing': 'immediately'});
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await leave(tester);
    expect(gateIsUp(tester), isTrue);
    expect(
      preferences.appLockClosed,
      isTrue,
      reason: 'and it is written down, so the process dying cannot open it',
    );
  });

  testWidgets('only when I ask: leaving does not close it', (tester) async {
    final services = await boot({'security.lock_timing': 'manual'});
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await leave(tester);
    expect(gateIsUp(tester), isFalse);
    expect(preferences.appLockClosed, isFalse);

    // Leaving is still recorded. The timing can be changed while the app is
    // away, and "after a minute" needs to know when the app was last open.
    expect(preferences.appLockLeftAt, isNotNull);
  });

  testWidgets('after a while: a short trip away leaves it open', (
    tester,
  ) async {
    final services = await boot({
      'security.lock_timing': 'after',
      'security.lock_grace_seconds': 300,
      // Left five seconds ago, which is well inside five minutes.
      'security.lock_left_at': DateTime.now()
          .subtract(const Duration(seconds: 5))
          .millisecondsSinceEpoch,
    });
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(
      gateIsUp(tester),
      isFalse,
      reason: 'a cold start inside the grace period is still inside it',
    );
  });

  testWidgets('after a while: a long trip away closes it', (tester) async {
    final services = await boot({
      'security.lock_timing': 'after',
      'security.lock_grace_seconds': 60,
      'security.lock_left_at': DateTime.now()
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
    });
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(gateIsUp(tester), isTrue);
  });

  testWidgets('a lock left closed stays closed through a restart', (
    tester,
  ) async {
    // The case "only when I ask" would otherwise lose: the user locks it by
    // hand, Android stops the process, and a flag held in memory goes with it.
    final services = await boot({
      'security.lock_timing': 'manual',
      'security.lock_closed': true,
    });
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(gateIsUp(tester), isTrue);
  });

  testWidgets('never left, never recorded: a first launch locks', (
    tester,
  ) async {
    // Not knowing how long the app has been away is not a reason to open it.
    final services = await boot({
      'security.lock_timing': 'after',
      'security.lock_grace_seconds': 60,
    });
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(gateIsUp(tester), isTrue);
  });
}
