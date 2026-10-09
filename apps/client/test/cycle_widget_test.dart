import 'dart:async';
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

  test('a Cycle write that was mid-flight when the lock closed does not '
      'republish the dates (SEC-09)', () async {
    final tmp = Directory.systemTemp.createTempSync('nex_cycle_race_');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(tmp.path);
    SharedPreferences.setMockInitialValues({'cycle.set_up': true});
    final prefs = await NexPreferences.load();
    final db = InProcessDb(dbPath: '${tmp.path}/nex.sqlite', deviceId: 'test');
    final services = NexServices.forTest(
      worker: db,
      deviceId: 'test',
      preferences: prefs,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: db.dbPath,
      mediaDir: '${tmp.path}/media',
      backupDir: '${tmp.path}/backups',
    );
    final file = File('${tmp.path}/${NexCycleWidgetSnapshot.fileName}');
    final published = <String>[];
    const channel = MethodChannel('nex/os_capture');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pushWidgets' && file.existsSync()) {
            published.add(file.readAsStringSync());
          }
          return null;
        });
    final overrides = _PausingCycleWrites();
    final oldOverrides = IOOverrides.current;
    IOOverrides.global = overrides;
    final bridge = NexWidgetBridge(services: services, preferences: prefs);
    try {
      await services.cycleStartPeriod(DateTime(2026, 10, 1));
      await bridge.start();
      expect(file.readAsStringSync(), contains('2026-10-01'));

      overrides.pause = true;
      final oldWrite = bridge.refresh();
      await overrides.entered.future;
      await prefs.setAppLockEnabled(true);
      await prefs.setAppLockClosed(true);
      await bridge.refresh();
      published.clear();
      overrides.resume.complete();
      await oldWrite;

      expect(jsonDecode(file.readAsStringSync()), {
        'version': 1,
        'state': 'locked',
      });
      for (final snapshot in published) {
        expect(snapshot, isNot(contains('2026-10-01')));
      }
    } finally {
      if (!overrides.resume.isCompleted) overrides.resume.complete();
      IOOverrides.global = oldOverrides;
      bridge.dispose();
      await services.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      PathProviderPlatform.instance = oldPaths;
      tmp.deleteSync(recursive: true);
    }
  });
}

/// Holds the next write of the Cycle widget's temporary file until told to
/// go on: the await the lock can close during.
class _PausingCycleWrites extends IOOverrides {
  bool pause = false;
  final entered = Completer<void>();
  final resume = Completer<void>();

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.endsWith('${NexCycleWidgetSnapshot.fileName}.tmp')
        ? _PausingFile(file, this)
        : file;
  }
}

class _PausingFile implements File {
  _PausingFile(this._inner, this._gate);

  final File _inner;
  final _PausingCycleWrites _gate;

  @override
  String get path => _inner.path;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    if (_gate.pause) {
      _gate.pause = false;
      _gate.entered.complete();
      await _gate.resume.future;
    }
    await _inner.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    return this;
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => _inner.writeAsStringSync(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );

  @override
  File renameSync(String newPath) => _inner.renameSync(newPath);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
