import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/backup_policy.dart';
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

class _PausedDb extends InProcessDb {
  _PausedDb({required super.dbPath, required super.deviceId});
  bool pause = false;
  final entered = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<List<Note>> timeline({
    int limit = 200,
    int offset = 0,
    String? tagId,
  }) async {
    final notes = await super.timeline(
      limit: limit,
      offset: offset,
      tagId: tagId,
    );
    if (pause) {
      pause = false;
      entered.complete();
      await resume.future;
    }
    return notes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'locking clears immediately and a pending unlocked read cannot republish content',
    () async {
      final tmp = Directory.systemTemp.createTempSync('nex_widget_race_');
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(tmp.path);
      SharedPreferences.setMockInitialValues({});
      final prefs = await NexPreferences.load();
      final db = _PausedDb(dbPath: '${tmp.path}/nex.sqlite', deviceId: 'test');
      final services = NexServices.forTest(
        worker: db,
        deviceId: 'test',
        preferences: prefs,
        backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
        dbPath: db.dbPath,
        mediaDir: '${tmp.path}/media',
        backupDir: '${tmp.path}/backups',
      );
      final bridge = NexWidgetBridge(services: services, preferences: prefs);
      final file = File('${tmp.path}/${NexWidgetSnapshotCache.fileName}');
      final snapshots = <String>[];
      const channel = MethodChannel('nex/os_capture');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'pushWidgets') {
              snapshots.add(file.readAsStringSync());
            }
            return null;
          });
      try {
        await services.captureText('private note');
        await bridge.start();
        expect(file.readAsStringSync(), contains('private note'));
        snapshots.clear();
        db.pause = true;
        final oldWrite = bridge.refresh();
        await db.entered.future;
        await prefs.setAppLockEnabled(true);
        await prefs.setAppLockClosed(true);
        await bridge.refresh();
        expect(jsonDecode(file.readAsStringSync())['notes'], isEmpty);
        db.resume.complete();
        await oldWrite;
        expect(snapshots, isNotEmpty);
        for (final snapshot in snapshots) {
          expect(snapshot, isNot(contains('private note')));
          expect(jsonDecode(snapshot)['appLock'], isTrue);
        }
      } finally {
        if (!db.resume.isCompleted) db.resume.complete();
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
