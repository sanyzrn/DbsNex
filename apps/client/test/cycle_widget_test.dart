import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/cycle_widget.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/nex_widget.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_process_db.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// The Cycle widgets' file: dates and numbers only, empty while locked or
/// off, and kept up to date as the cycle changes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the snapshot', () {
    final start = CycleDate(2026, 9, 20);
    final periods = [CyclePeriod(id: 'p', start: start, end: start.addDays(4))];
    final prediction = CyclePredictor.predict(
      periods: periods,
      today: start.addDays(10),
      typicalCycle: 28,
      typicalPeriod: 5,
    );

    Map<String, Object?> build({
      bool enabled = true,
      bool setUp = true,
      bool hidden = false,
      CycleMode mode = CycleMode.normal,
    }) => NexCycleWidgetSnapshot.build(
      enabled: enabled,
      setUp: setUp,
      hidden: hidden,
      mode: mode,
      periods: periods,
      prediction: prediction,
      pregnancyStart: start,
    );

    test('off, locked and not set up carry nothing but the state', () {
      expect(build(enabled: false), {'version': 1, 'state': 'off'});
      expect(build(hidden: true), {'version': 1, 'state': 'locked'});
      expect(build(setUp: false), {'version': 1, 'state': 'setup'});
    });

    test('ready: dates the widget counts from, nothing else', () {
      final json = build();
      expect(json['state'], 'ready');
      expect(json['lastStart'], '2026-09-20');
      expect(json['periodEnd'], '2026-09-24');
      expect(json['nextStart'], '${prediction!.nextStart}');
      expect(json['averageCycle'], 28);
      expect(json.keys, isNot(contains('note')));
      expect(json.keys, isNot(contains('symptoms')));
    });

    test('pregnant counts from the pregnancy, without predictions', () {
      final json = build(mode: CycleMode.pregnant);
      expect(json['pregnancyStart'], '2026-09-20');
      expect(json.containsKey('nextStart'), isFalse);
    });
  });

  test(
    'the bridge writes it, and rewrites it when the cycle changes',
    () async {
      final tmp = Directory.systemTemp.createTempSync('nex_cycle_widget_');
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(tmp.path);
      SharedPreferences.setMockInitialValues({'cycle.set_up': true});
      final prefs = await NexPreferences.load();
      final db = InProcessDb(
        dbPath: '${tmp.path}/nex.sqlite',
        deviceId: 'test',
      );
      final services = NexServices.forTest(
        worker: db,
        deviceId: 'test',
        preferences: prefs,
        backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
        dbPath: db.dbPath,
        mediaDir: '${tmp.path}/media',
        backupDir: '${tmp.path}/backups',
      );
      const channel = MethodChannel('nex/os_capture');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      final bridge = NexWidgetBridge(services: services, preferences: prefs);
      final file = File('${tmp.path}/${NexCycleWidgetSnapshot.fileName}');
      Map<String, Object?> read() =>
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      try {
        await bridge.start();
        expect(read()['state'], 'ready');
        expect(read().containsKey('lastStart'), isFalse);

        await services.cycleStartPeriod(DateTime(2026, 10, 1));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await bridge.refresh();
        expect(read()['lastStart'], '2026-10-01');

        // The lock closing empties it, like the notes snapshot.
        await prefs.setAppLockEnabled(true);
        await prefs.setAppLockClosed(true);
        await bridge.refresh();
        expect(read(), {'version': 1, 'state': 'locked'});
      } finally {
        bridge.dispose();
        await services.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        PathProviderPlatform.instance = oldPaths;
        tmp.deleteSync(recursive: true);
      }
    },
  );
}
