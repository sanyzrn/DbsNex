import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/app_lock.dart';
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

  /// Backgrounds the app and lets the write that follows actually land.
  ///
  /// `didChangeAppLifecycleState` is a synchronous callback, so the lock
  /// state is written without being awaited — there is nothing to await it
  /// from. A single `pump` gets the rebuild but not the platform-channel
  /// round trip behind `SharedPreferences`, which is why this settles.
  Future<void> leave(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
  }

  bool gateIsUp(WidgetTester tester) =>
      find.byKey(appLockBarrierKey).evaluate().isNotEmpty;

  testWidgets('immediately: leaving closes it', (tester) async {
    final services = await boot({'security.lock_timing': 'immediately'});
    await tester.pumpWidget(
      NexApp(
        services: services,
        preferences: preferences,
        appLock: _AlwaysRefused(),
      ),
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
      NexApp(
        services: services,
        preferences: preferences,
        appLock: _AlwaysRefused(),
      ),
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
      NexApp(
        services: services,
        preferences: preferences,
        appLock: _AlwaysRefused(),
      ),
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
      NexApp(
        services: services,
        preferences: preferences,
        appLock: _AlwaysRefused(),
      ),
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
      NexApp(
        services: services,
        preferences: preferences,
        appLock: _AlwaysRefused(),
      ),
    );
    await tester.pumpAndSettle();

    expect(gateIsUp(tester), isTrue);
  });

  testWidgets('after a while: the lock closes while the app is away', (
    tester,
  ) async {
    // It used to be decided only on the way back in, which is invisible to
    // everyone except the person returning — the home-screen widget went on
    // showing a library the app still considered open.
    final services = await boot({
      'security.lock_timing': 'after',
      'security.lock_grace_seconds': 60,
      'security.lock_left_at': DateTime.now().millisecondsSinceEpoch,
    });
    await tester.pumpWidget(
      NexApp(
        services: services,
        preferences: preferences,
        appLock: _AlwaysRefused(),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateIsUp(tester), isFalse, reason: 'just left, still inside it');

    await leave(tester);
    expect(gateIsUp(tester), isFalse, reason: 'the grace has not run out');

    await tester.pump(const Duration(seconds: 61));
    // Settled for the same reason `leave` settles: the write behind the flag
    // is not awaited from a timer callback either.
    await tester.pumpAndSettle();
    expect(gateIsUp(tester), isTrue);
    expect(
      preferences.appLockClosed,
      isTrue,
      reason: 'written down, so the widget and the next launch both see it',
    );
  });

  testWidgets('unlocking is not undone by the prompt closing', (tester) async {
    // The bug: the OS fingerprint sheet pauses and resumes the app, and every
    // one of those resumes measured the same long-past `leftAt`, decided the
    // grace had run out, re-locked and prompted again — fingerprint after
    // fingerprint with no way out but force-stopping Nex.
    final services = await boot({
      'security.lock_timing': 'after',
      'security.lock_grace_seconds': 60,
      'security.lock_left_at': DateTime.now()
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
    });
    await tester.pumpWidget(
      NexApp(
        services: services,
        preferences: preferences,
        appLock: _PromptThatTakesTheForeground(tester),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateIsUp(tester), isFalse, reason: 'the prompt was answered');

    // What Android sends when the sheet comes down.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(gateIsUp(tester), isFalse);
    expect(preferences.appLockClosed, isFalse);
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
      NexApp(
        services: services,
        preferences: preferences,
        appLock: _AlwaysRefused(),
      ),
    );
    await tester.pumpAndSettle();

    expect(gateIsUp(tester), isTrue);
  });
}

/// A prompt that refuses, and does it before the next line of the test runs.
///
/// None of these tests is about the fingerprint — they are about when the gate
/// goes up. What they cannot tolerate is an unlock attempt still in flight
/// when the app is backgrounded, because that is deliberately treated as "the
/// system's own sheet is up", not as leaving, and the lock is then not closed.
/// A real `local_auth` in a test process answers false too, just not at any
/// particular moment.
class _AlwaysRefused extends AppLockService {
  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async => false;
}

/// A prompt that accepts — and pauses the app on its way up, the way the
/// real one does.
///
/// That detail is the test: Android backgrounds Nex to put its own sheet in
/// front, so the pause arrives while an unlock is in flight and is ignored on
/// purpose. What comes back afterwards is a bare `resumed`, with nothing
/// having recorded that the app was ever open in between.
class _PromptThatTakesTheForeground extends AppLockService {
  _PromptThatTakesTheForeground(this.tester);

  final WidgetTester tester;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    return true;
  }
}
