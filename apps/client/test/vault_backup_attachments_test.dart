import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:nex_client/platform/vault_files.dart';
import 'package:nex_client/platform/vault_store.dart';
import 'package:nex_client/platform/full_backup.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'full backup restores attachments on a new device without replacing existing files/key',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final root = Directory.systemTemp.createTempSync('nex-vault-backup-');
      final oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(root.path);
      addTearDown(() {
        PathProviderPlatform.instance = oldPaths;
        root.deleteSync(recursive: true);
      });
      final source = VaultFiles(
        root: () async => Directory('${root.path}/old'),
      );
      final bytes = Uint8List.fromList('private photo bytes'.codeUnits);
      final id = await source.put(bytes);
      final snapshot = VaultSnapshot([
        VaultEntry(
          id: 'message',
          kind: VaultKind.message,
          fields: {'file': id, 'fileKind': 'photo'},
          updatedAt: DateTime.utc(2026),
        ),
      ], null);
      final bundle = (await source.exportBackup(
        snapshot,
        '${root.path}/files.zip',
      ))!;
      final key = FullBackup.newKey();
      final library = File('${root.path}/library')
        ..writeAsStringSync('library');
      final backup = '${root.path}/full.nexfull';
      FullBackup.create(
        library: library.path,
        output: backup,
        key: key,
        vaultFiles: bundle.path,
        settings: {
          'vault': snapshot.toJson(),
          'vaultFilesKey': bundle.key,
          'vaultFilesSha256': bundle.sha256,
        },
      );
      expect(FullBackup.isFullBackup(backup), isTrue);
      final replacedBundle = File('${root.path}/replaced.zip')
        ..writeAsBytesSync([1, 2, 3]);
      final tampered = '${root.path}/tampered.nexfull';
      FullBackup.create(
        library: library.path,
        output: tampered,
        key: key,
        vaultFiles: replacedBundle.path,
        settings: {
          'vault': snapshot.toJson(),
          'vaultFilesKey': bundle.key,
          'vaultFilesSha256': bundle.sha256,
        },
      );
      expect(
        () => FullBackup.unpack(
          tampered,
          '${root.path}/tampered-out',
          key,
          modelHash: 'none',
          modelBytes: 0,
        ),
        throwsFormatException,
      );
      final settings = FullBackup.unpack(
        backup,
        '${root.path}/unpack',
        key,
        modelHash: 'none',
        modelBytes: 0,
      );
      FlutterSecureStorage.setMockInitialValues(
        {},
      ); // A different installation/key.
      final target = VaultFiles(
        root: () async => Directory('${root.path}/new'),
      );
      final existing = await target.put(Uint8List.fromList([8, 9]));
      const storage = FlutterSecureStorage();
      final targetKey = await storage.read(key: VaultFiles.keyName);
      final restored = await target.restoreBackup(
        VaultSnapshot.fromJson(
          Map<String, dynamic>.from(settings['vault'] as Map),
        ),
        '${root.path}/unpack/vault-files.zip',
        settings['vaultFilesKey'] as String,
      );
      final restoredId = restored.entries.single.value('file');
      expect(restoredId, isNot(id));
      expect(await target.get(restoredId), bytes);
      expect(await target.get(existing), [8, 9]);
      expect(await storage.read(key: VaultFiles.keyName), targetKey);
      final firstCopy = await target.openCopy(restoredId, 'photo.bin');
      final secondCopy = await target.openCopy(restoredId, 'photo.bin');
      expect(secondCopy.path, firstCopy.path);
      expect(await secondCopy.readAsBytes(), bytes);
      await expectLater(
        target.restoreBackup(snapshot, bundle.path, FullBackup.newKey()),
        throwsA(anything),
      );
      expect(await target.get(existing), [8, 9]);
    },
  );
  test(
    'missing referenced attachment fails instead of producing an incomplete vault backup',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final root = Directory.systemTemp.createTempSync('nex-vault-missing-');
      addTearDown(() => root.deleteSync(recursive: true));
      final files = VaultFiles(root: () async => root);
      final id = await files.put(Uint8List.fromList([1]));
      await files.delete(id);
      final snapshot = VaultSnapshot([
        VaultEntry(
          id: 'm',
          kind: VaultKind.message,
          fields: {'file': id},
          updatedAt: DateTime.utc(2026),
        ),
      ], null);
      await expectLater(
        files.exportBackup(snapshot, '${root.path}/files.zip'),
        throwsA(anything),
      );
    },
  );
  test(
    'plaintext replacement settings cannot bypass recovery-code authentication',
    () {
      final root = Directory.systemTemp.createTempSync('nex-forged-settings-');
      addTearDown(() => root.deleteSync(recursive: true));
      final key = FullBackup.newKey();
      final library = File('${root.path}/library')
        ..writeAsStringSync('library');
      final backup = '${root.path}/full.nexfull';
      FullBackup.create(
        library: library.path,
        output: backup,
        key: key,
        settings: {'version': 1},
      );
      final outer = ZipDecoder().decodeBytes(File(backup).readAsBytesSync());
      final plaintext = ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile.string('settings.json', '{"version":1}')),
      );
      final forged = Archive();
      for (final entry in outer) {
        forged.addFile(
          entry.name == 'settings.aes.zip'
              ? ArchiveFile('settings.aes.zip', plaintext.length, plaintext)
              : entry,
        );
      }
      File(backup).writeAsBytesSync(ZipEncoder().encode(forged));
      expect(
        () => FullBackup.unpack(
          backup,
          '${root.path}/out',
          key,
          modelHash: 'none',
          modelBytes: 0,
        ),
        throwsFormatException,
      );
      expect(File('${root.path}/out/library.nexbak').existsSync(), isFalse);
    },
  );
}
