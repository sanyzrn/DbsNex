import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/nex_widget.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_process_db.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// The recap on the home screen must stop being shown when it stops being
/// true — even if the app never opens again. The file carries the expiry,
/// and the bridge rewrites it at that instant so the words leave the disk
/// as well as the render.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('an expired recap leaves the snapshot without a new capture', () async {
    final tmp = Directory.systemTemp.createTempSync('nex_widget_expiry_');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(tmp.path);
    SharedPreferences.setMockInitialValues({});
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
    final bridge = NexWidgetBridge(services: services, preferences: prefs);
    final file = File('${tmp.path}/${NexWidgetSnapshotCache.fileName}');
    const channel = MethodChannel('nex/os_capture');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    try {
      final now = DateTime.now();
      await prefs.setAiDaySummary(
        text: 'nothing is overdue',
        dateKey: NexPreferences.daySummaryDateKey(now),
        source: 'fixture',
        validUntil: now.add(const Duration(milliseconds: 300)),
      );
      await bridge.start();
      final first = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(first['recap'], 'nothing is overdue');
      expect(
        first['recapValidUntil'],
        now.add(const Duration(milliseconds: 300)).millisecondsSinceEpoch,
      );
      // No capture, no preference change, no app return: the expiry alone
      // must rewrite the file. Poll rather than sleep a fixed span so the
      // test is quick on a fast machine and patient on a loaded one.
      Map<String, Object?>? after;
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        if (json['recap'] == '') {
          after = json;
          break;
        }
      }
      expect(after, isNotNull, reason: 'the expired recap must leave the file');
      expect(after!.containsKey('recapValidUntil'), isFalse);
    } finally {
      bridge.dispose();
      await services.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      PathProviderPlatform.instance = oldPaths;
      tmp.deleteSync(recursive: true);
    }
  });
}
