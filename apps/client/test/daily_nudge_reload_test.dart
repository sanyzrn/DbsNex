import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/daily_nudge.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/in_process_db.dart';

/// Rebuilding the daily-nudge plan runs after every debounced library
/// change, and the common answer is "nothing moved". The plan key proves
/// that without touching the preferences file — the full re-read
/// (`SharedPreferences.reload`) now happens only when a plan is really going
/// to be rebuilt, because it ran on every no-op pass.
class _CountingStore extends InMemorySharedPreferencesStore {
  _CountingStore(super.data) : super.withData();

  int getAllCalls = 0;

  @override
  Future<Map<String, Object>> getAll() {
    getAllCalls++;
    return super.getAll();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late _CountingStore store;
  late NexPreferences preferences;
  late NexServices services;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    NexReminders.debugSupported = true;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pluginChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    messenger.setMockMethodCallHandler(
      pluginChannel,
      (call) async => switch (call.method) {
        'initialize' => true,
        'pendingNotificationRequests' => <Object>[],
        'getNotificationAppLaunchDetails' => {'notificationLaunchedApp': false},
        _ => null,
      },
    );
    const nudgeChannel = MethodChannel('nex/daily_nudge');
    messenger.setMockMethodCallHandler(
      nudgeChannel,
      (call) async => call.method == 'configure' ? true : null,
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      NexReminders.debugSupported = null;
      messenger.setMockMethodCallHandler(pluginChannel, null);
      messenger.setMockMethodCallHandler(nudgeChannel, null);
    });

    final initial = <String, Object>{
      'onboarding.complete': true,
      'nudge.on': true,
      'nudge.at': 9 * 60,
    };
    SharedPreferences.setMockInitialValues(initial);
    // Seeded the way `setMockInitialValues` seeds its own store: the plugin's
    // reads are prefixed, and `getAll` answers only prefixed keys.
    store = _CountingStore({
      for (final entry in initial.entries) 'flutter.${entry.key}': entry.value,
    });
    SharedPreferencesStorePlatform.instance = store;

    tmp = Directory.systemTemp.createTempSync('nex_nudge_reload_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    Directory(p.join(tmp.path, 'media')).createSync(recursive: true);
    Directory(p.join(tmp.path, 'backups')).createSync(recursive: true);
    preferences = await NexPreferences.load();
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: preferences,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: p.join(tmp.path, 'media'),
      backupDir: p.join(tmp.path, 'backups'),
    );
  });

  tearDown(() async {
    await services.dispose();
    preferences.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('an unchanged library rebuilds nothing and re-reads nothing', () async {
    await services.captureText('the only note');

    // First pass: the plan is built, armed, and the re-reads it owes
    // happened (the shade hand-off settle, and the plan's own receipts).
    await DailyNudge.apply(services: services);
    final afterFirst = store.getAllCalls;
    expect(afterFirst, greaterThan(0));

    // Second pass with nothing changed: the plan key answers, and the only
    // re-read left is the one the shade hand-off settle must make — the
    // notification isolate writes acknowledgements behind this cache. The
    // plan's own re-read is gone; there used to be two.
    await DailyNudge.apply(services: services);
    expect(
      store.getAllCalls,
      afterFirst + 1,
      reason: 'a no-op pass pays only the hand-off settle, not the plan',
    );

    // A real change rebuilds — and re-reads for the plan again, as before.
    await services.captureText('a second note');
    await DailyNudge.apply(services: services);
    expect(store.getAllCalls, greaterThan(afterFirst + 1));
  });
}
