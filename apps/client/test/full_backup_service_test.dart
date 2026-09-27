import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/full_backup.dart';
import 'package:nex_client/platform/vault_store.dart';
import 'support/in_process_db.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'complete backup restores library and settings together and clears recovery journal',
    () async {
      final root = Directory.systemTemp.createTempSync('nex-full-service-');
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(root.path);
      addTearDown(() {
        PathProviderPlatform.instance = oldPaths;
        root.deleteSync(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final preferences = await NexPreferences.load();
      final media = Directory('${root.path}/media')..createSync();
      final backups = Directory('${root.path}/backups')..createSync();
      final db = '${root.path}/nex.sqlite';
      final services = NexServices.forTest(
        worker: InProcessDb(dbPath: db, deviceId: 'test'),
        deviceId: 'test',
        preferences: preferences,
        backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
        dbPath: db,
        mediaDir: media.path,
        backupDir: backups.path,
      );
      addTearDown(services.dispose);
      await preferences.attachProfileMirror(media.path);
      await preferences.setDisplayName('Original profile');
      final note = (await services.captureText('Original text'))!;
      final key = FullBackup.newKey();
      VaultEntry secret(String value) => VaultEntry(
        id: 'vault-one',
        kind: VaultKind.password,
        fields: {'title': 'Private account', 'password': value},
        updatedAt: DateTime.utc(2026),
      );
      final vault = VaultStore();
      await vault.save(secret('original-vault-secret'));
      final ordinary = await services.exportFullBackup(
        key,
        includeModel: false,
      );
      final ordinarySettings = FullBackup.unpack(
        ordinary,
        '${root.path}/ordinary',
        key,
        modelHash: 'unused',
        modelBytes: 0,
      );
      expect(ordinarySettings.containsKey('vault'), isFalse);
      final backup = await services.exportFullBackup(
        key,
        includeModel: false,
        includeVault: true,
      );
      await vault.save(secret('changed-vault-secret'));
      await services.updateNote(note.id, 'Changed text');
      await preferences.setDisplayName('Changed profile');
      await expectLater(
        services.restoreFullBackup(File(backup), key),
        throwsA(isA<VaultAuthenticationRequired>()),
      );
      expect(preferences.displayName, 'Changed profile');
      expect(
        (await vault.read()).entries.single.value('password'),
        'changed-vault-secret',
      );
      final result = await services.restoreFullBackup(
        File(backup),
        key,
        allowVaultRestore: true,
      );
      expect(
        (await vault.read()).entries.single.value('password'),
        'original-vault-secret',
      );
      expect(result.error, isNull);
      expect(preferences.displayName, 'Original profile');
      expect(await preferences.pendingRestoreRecovery(), isNull);
      final restored = NexDatabase.open(db);
      try {
        expect(
          SqliteNoteRepository(restored).getById(note.id)?.content,
          'Original text',
        );
      } finally {
        restored.close();
      }
    },
  );
}
