import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/full_backup.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/nex_harness.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _FailingStorage extends TestFlutterSecureStoragePlatform {
  _FailingStorage() : super({});
  bool failCredential = false;
  bool failJournalDelete = false;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (key == 'ai.key.openai' && failCredential) {
      failCredential = false;
      throw StateError('Simulated secure write failure');
    }
    await super.write(key: key, value: value, options: options);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    if (key == 'nex.full_restore.recovery' && failJournalDelete) {
      throw StateError('Simulated undo cleanup failure');
    }
    await super.delete(key: key, options: options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NexTestHarness h;
  late PathProviderPlatform oldPaths;
  late _FailingStorage storage;

  setUp(() async {
    storage = _FailingStorage();
    FlutterSecureStoragePlatform.instance = storage;
    h = await NexTestHarness.create(name: 'nex-restore-safety-');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(h.root.path);
    await h.preferences.setDisplayName('Current profile');
  });
  tearDown(() async {
    await h.dispose();
    PathProviderPlatform.instance = oldPaths;
  });

  Future<File> libraryBackup() async {
    await h.services.backupNow();
    return (await h.services.listBackups()).first;
  }

  File futureBackup() {
    final path = '${h.root.path}/future.sqlite';
    final db = NexDatabase.open(path);
    db.db.execute('PRAGMA user_version = ${NexDatabase.schemaVersion + 1}');
    db.close();
    final bytes = File(path).readAsBytesSync();
    final zip = Archive()
      ..addFile(ArchiveFile('nex.sqlite', bytes.length, bytes));
    return File('${h.root.path}/future.nexbak')
      ..writeAsBytesSync(ZipEncoder().encode(zip));
  }

  for (final full in [false, true]) {
    test(
      'a newer library, full=$full, is refused with the session still usable',
      () async {
        final original = (await h.services.captureText('Current note'))!;
        var selected = futureBackup();
        final key = FullBackup.newKey();
        if (full) {
          final output = '${h.root.path}/future.nexfull';
          FullBackup.create(
            library: selected.path,
            output: output,
            settings: h.preferences.backupSettings(),
            key: key,
          );
          selected = File(output);
        }
        await expectLater(
          full
              ? h.services.restoreFullBackup(selected, key)
              : h.services.restoreBackup(selected),
          throwsA(isA<NewerLibraryException>()),
        );
        expect(
          (await h.services.getById(original.id))!.content,
          'Current note',
        );
        expect(await h.services.captureText('Still writable'), isNotNull);
        expect(h.preferences.displayName, 'Current profile');
        expect(await h.preferences.pendingRestoreRecovery(), isNull);
        expect(
          Directory('${h.backupDir}/before-restore').existsSync(),
          isFalse,
        );
      },
    );
  }

  test(
    'a full restore that cannot install its library leaves no armed undo',
    () async {
      final image = File('${h.mediaDir}/photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final photo = await h.db.capturePhoto(
        mediaUri: image.path,
        mediaHash: sha256OfBytes(Uint8List.fromList([1, 2, 3])),
      );
      final note = (await h.services.captureText('Live note'))!;
      final library = await h.services.portableBackup(await libraryBackup());
      // A self-contained backup whose database still points at the photo,
      // but which carries no media entry. Validation cannot see that — the
      // media is only matched while staging — so this fails *after* the
      // service has closed its database and begun the full restore, which is
      // exactly the window the undo journal used to survive.
      final archive = ZipDecoder().decodeBytes(File(library).readAsBytesSync());
      final incomplete = Archive();
      for (final entry in archive.files) {
        if (!entry.name.startsWith('media/')) incomplete.addFile(entry);
      }
      final broken = File('${h.root.path}/incomplete.nexbak')
        ..writeAsBytesSync(ZipEncoder().encode(incomplete));
      image.deleteSync();
      final key = FullBackup.newKey();
      final output = '${h.root.path}/incomplete.nexfull';
      FullBackup.create(
        library: broken.path,
        output: output,
        settings: h.preferences.backupSettings(),
        key: key,
      );

      final result = await h.services.restoreFullBackup(File(output), key);
      expect(result.error, isNotNull);
      // The restore transaction put the live library back; settings were
      // never touched. Nothing is pending, so the next launch must not
      // “roll back” to this safety copy and drop everything written since.
      expect(await h.preferences.pendingRestoreRecovery(), isNull);
      expect(
        Directory(h.backupDir)
            .listSync()
            .whereType<Directory>()
            .where((dir) => p.basename(dir.path).startsWith('full-restore-')),
        isEmpty,
        reason: 'the unused safety copy must not linger in the backups folder',
      );
      final reopened = NexDatabase.open(h.dbPath);
      try {
        final kept = SqliteNoteRepository(reopened);
        expect(kept.getById(note.id)!.content, 'Live note');
        expect(kept.getById(photo.id), isNotNull);
      } finally {
        reopened.close();
      }
    },
  );

  test(
    'a healthy backup repairs missing live media and keeps a rescue copy',
    () async {
      final image = File('${h.mediaDir}/photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final photo = await h.db.capturePhoto(
        mediaUri: image.path,
        mediaHash: sha256OfBytes(Uint8List.fromList([1, 2, 3])),
      );
      final backup = await libraryBackup();
      image.deleteSync();
      final result = await h.services.restoreBackup(backup);
      expect(result.error, isNull);
      expect(image.readAsBytesSync(), [1, 2, 3]);
      final reopened = NexDatabase.open(h.dbPath);
      expect(SqliteNoteRepository(reopened).getById(photo.id), isNotNull);
      reopened.close();
      final safety = Directory('${h.backupDir}/before-restore')
          .listSync()
          .whereType<File>()
          .singleWhere((f) => f.path.endsWith('.nexbak'));
      expect(NexBackupArchive.missingMedia(safety.path), ['photo.jpg']);
    },
  );

  test(
    'malformed full-backup appearance is rejected before changing data',
    () async {
      final note = (await h.services.captureText('Current note'))!;
      final library = await libraryBackup();
      final settings = h.preferences.backupSettings();
      (settings['preferences'] as Map)['appearance.ui_scale'] = 'invalid';
      final output = '${h.root.path}/invalid.nexfull';
      final key = FullBackup.newKey();
      FullBackup.create(
        library: library.path,
        output: output,
        settings: settings,
        key: key,
      );
      await expectLater(
        h.services.restoreFullBackup(File(output), key),
        throwsFormatException,
      );
      expect((await h.services.getById(note.id))!.content, 'Current note');
      expect(await h.preferences.pendingRestoreRecovery(), isNull);
    },
  );

  test(
    'an integer UI scale in a legacy full settings backup opens as a double',
    () async {
      final settings = h.preferences.backupSettings();
      (settings['preferences'] as Map)['appearance.ui_scale'] = 1;
      await h.preferences.restoreSettings(settings);
      expect(h.preferences.uiScale, 1.0);
      final reloaded = await NexPreferences.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.uiScale, 1.0);
    },
  );

  test(
    'retired theme names in a full backup retain safe app fallbacks',
    () async {
      final settings = h.preferences.backupSettings();
      (settings['preferences'] as Map<String, Object?>).addAll({
        'appearance.theme': 'legacy-mode',
        'appearance.theme_preset': 'Retired Theme',
      });
      await h.preferences.restoreSettings(settings);
      expect(h.preferences.appearanceMode, NexAppearanceMode.system);
      expect(h.preferences.effectiveThemePreset, 'classic');
    },
  );

  test('two restores cannot interleave safety copies and live swaps', () async {
    await h.services.captureText('Current note');
    final backup = await libraryBackup();
    final first = h.services.restoreBackup(backup);
    await expectLater(h.services.restoreBackup(backup), throwsStateError);
    expect((await first).error, isNull);
  });

  test('failed settings installation retains undo for the original library and credentials', () async {
    final note = (await h.services.captureText('Backup note'))!;
    await h.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'backup-key'),
    );
    final key = FullBackup.newKey();
    final backup = await h.services.exportFullBackup(key, includeModel: false);
    await h.services.updateNote(note.id, 'Newer live edit');
    await h.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'live-key'),
    );
    await h.preferences.setDisplayName('Newer live profile');
    storage.failCredential = true;
    final result = await h.services.restoreFullBackup(File(backup), key);
    expect(result.error, isNotNull);
    final undo = (await h.preferences.pendingRestoreRecovery())!;
    expect(undo['modelId'], isA<String>());
    // The same recovery sequence bootstrap performs before opening any worker.
    NexBackupArchive.restore(
      liveDbPath: h.dbPath,
      mediaDir: h.mediaDir,
      backupFile: undo['library'] as String,
    );
    await h.preferences.restoreSettings(
      Map<String, dynamic>.from(undo['settings'] as Map),
    );
    await h.preferences.finishRestoreRecovery();
    final reopened = NexDatabase.open(h.dbPath);
    expect(
      SqliteNoteRepository(reopened).getById(note.id)!.content,
      'Newer live edit',
    );
    reopened.close();
    expect(h.preferences.displayName, 'Newer live profile');
    expect(h.preferences.aiProvider.apiKey, 'live-key');
    expect(await h.preferences.pendingRestoreRecovery(), isNull);
  });

  test(
    'undo cleanup failure after commit cannot reactivate recovery',
    () async {
      await h.preferences.beginRestoreRecovery('${h.root.path}/safety.nexbak');
      storage.failJournalDelete = true;
      await h.preferences.finishRestoreRecovery();
      final reloaded = await NexPreferences.load();
      addTearDown(reloaded.dispose);
      expect(await reloaded.pendingRestoreRecovery(), isNull);
    },
  );
}
