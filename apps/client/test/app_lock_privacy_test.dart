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
import 'package:nex_client/platform/secure_window.dart';

import 'support/in_process_db.dart';

/// Two ways the app lock was showing the notes it exists to hide.
///
/// The report: with the lock on and the fingerprint prompt up, the whole
/// timeline was readable behind it — and the same notes sat in the recent-apps
/// screen, where no prompt is asked for at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nex/os_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late NexPreferences preferences;
  late List<MethodCall> calls;

  /// Builds the real app graph. Registers its own teardown so that the one
  /// case here which never boots an app does not trip over a `late` field.
  Future<NexServices> boot({
    required bool appLock,
    bool liquidGlass = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'onboarding.complete': true,
      'onboarding.tour_complete': true,
      'security.app_lock': appLock,
      'appearance.liquid_glass': liquidGlass,
    });
    final tmp = Directory.systemTemp.createTempSync('nex_app_lock_');
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
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// The argument of every `setSecure` since the last clear, in order.
  List<Object?> secureCalls() => [
    for (final call in calls)
      if (call.method == 'setSecure')
        (call.arguments as Map<Object?, Object?>)['on'],
  ];

  testWidgets('the lock gate is opaque even when the scaffold is not', (
    tester,
  ) async {
    // Liquid glass on, which is what the report was running. The theme then
    // sets `scaffoldBackgroundColor` to transparent on purpose — so the app's
    // own backdrop shows through every screen — and the lock gate was a bare
    // `Scaffold` inheriting exactly that.
    final services = await boot(appLock: true, liquidGlass: true);
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final gate = find.byKey(appLockBarrierKey);
    expect(gate, findsOneWidget, reason: 'the lock is on, so the gate is up');

    // The precondition the bug needed. Asserted rather than assumed: if the
    // theme ever stops doing this, the assertion below stops testing anything,
    // and this says so instead of passing quietly.
    expect(
      Theme.of(tester.element(gate)).scaffoldBackgroundColor.a,
      0.0,
      reason: 'the surrounding theme really is see-through',
    );

    // And the gate is not — over the whole window, not a panel in the middle
    // of one.
    expect(tester.widget<Scaffold>(gate).backgroundColor?.a, 1.0);
    expect(tester.getSize(gate), tester.getSize(find.byType(NexApp)));
  });

  testWidgets('the lock decides whether the OS may capture the window', (
    tester,
  ) async {
    // `FLAG_SECURE` is the only thing that blanks the recents thumbnail —
    // that picture is taken outside the app, off a frame Dart never draws, so
    // nothing painted here can hide from it. It follows the lock rather than
    // being always on: someone who never asked for a lock has not asked to
    // lose screenshots of their own notes either.
    final services = await boot(appLock: false);
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(secureCalls(), [false], reason: 'no lock, nothing withheld');

    calls.clear();
    await preferences.setAppLockEnabled(true);
    await tester.pump();
    expect(secureCalls(), [true]);

    // Every preference change arrives at the same listener, so one that has
    // nothing to do with the lock must not go back to the platform to repeat
    // itself.
    calls.clear();
    await preferences.setLiquidGlass(true);
    await tester.pump();
    expect(secureCalls(), isEmpty);

    await preferences.setAppLockEnabled(false);
    await tester.pump();
    expect(secureCalls(), [false], reason: 'turned off, and given back');
  });

  test('a platform with no native half is an absence, not a failure', () async {
    // Windows has no equivalent flag and nothing registers this channel there.
    // The app lock still locks, so this call cannot be allowed to throw out of
    // a preference listener that has other work after it.
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(NexSecureWindow.setSecure(true), completes);

    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'error'),
    );
    await expectLater(NexSecureWindow.setSecure(true), completes);
  });
}
