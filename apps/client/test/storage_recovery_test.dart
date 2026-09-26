import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/export_cache.dart';

class BrokenKeystore extends TestFlutterSecureStoragePlatform {
  BrokenKeystore() : super({});
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'key_unavailable');
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'key_unavailable');
}

void main() {
  test('sync credential survives preferences reload', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await NexPreferences.load();
    await first.setSyncBearerToken('test-token');
    final next = await NexPreferences.load();
    expect(next.syncBearerToken, 'test-token');
    first.dispose();
    next.dispose();
  });

  test(
    'keystore failure preserves legacy keys and does not block local preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'ai.key.openai': 'old-key',
        'sync.bearer_token': 'old-sync',
        'profile.name': 'Sara',
        'security.app_lock': true,
      });
      final normal = FlutterSecureStoragePlatform.instance;
      FlutterSecureStoragePlatform.instance = BrokenKeystore();
      final prefs = await NexPreferences.load();
      expect(prefs.secureStorageUnavailable, isTrue);
      expect(prefs.appLockEnabled, isTrue);
      expect(prefs.syncBearerToken, isNull);
      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('ai.key.openai'), 'old-key');
      expect(stored.getString('sync.bearer_token'), 'old-sync');
      expect(stored.getString('profile.name'), 'Sara');
      FlutterSecureStoragePlatform.instance = normal;
      final retry = await NexPreferences.load();
      expect(retry.syncBearerToken, 'old-sync');
      expect(stored.getString('sync.bearer_token'), isNull);
      prefs.dispose();
      retry.dispose();
    },
  );

  test(
    'export cleanup keeps recent shared files and unrelated files',
    () async {
      final dir = Directory.systemTemp.createTempSync('nex-cache-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final old = File('${dir.path}/Nex-2026-01-01.zip')
        ..writeAsStringSync('old');
      old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
      final current = File('${dir.path}/Nex-backup-123.nexbak')
        ..writeAsStringSync('current');
      final other = File('${dir.path}/installer.apk')
        ..writeAsStringSync('other');
      other.setLastModifiedSync(DateTime(2020));
      await cleanExportCache(dir);
      expect(old.existsSync(), isFalse);
      expect(current.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
    },
  );
}
