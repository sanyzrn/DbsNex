import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_folder.dart';
import 'package:nex_client/screens/backup_screen.dart';
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

/// Stands in for Android's folder: records what was copied into it.
class _FakeFolder implements NexBackupFolderChannel {
  bool reachableNow = true;
  bool copyWorks = true;
  final copies = <String>[];
  final released = <String>[];
  ({String uri, String name})? toPick = (
    uri: 'content://tree/drive',
    name: 'Drive',
  );

  @override
  bool get supported => true;

  @override
  Future<({String uri, String name})?> pick() async => toPick;

  @override
  Future<bool> reachable(String uri) async => reachableNow;

  @override
  Future<void> release(String uri) async => released.add(uri);

  @override
  Future<String?> copy(String uri, String path, String name) async {
    // The file has to be whole and there while Android copies it.
    expect(File(path).existsSync(), isTrue);
    expect(File(path).lengthSync(), greaterThan(0));
    if (!copyWorks) return 'write: IOException';
    copies.add(name);
    return null;
  }
}

void main() {
  late NexTestHarness harness;
  late _FakeFolder folder;
  late PathProviderPlatform oldPaths;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_folder_');
    oldPaths = PathProviderPlatform.instance;
    final cache = Directory('${harness.root.path}/cache')..createSync();
    PathProviderPlatform.instance = _Paths(cache.path);
    folder = _FakeFolder();
    harness.services.backupFolder = folder;
  });

  tearDown(() async {
    PathProviderPlatform.instance = oldPaths;
    await harness.dispose();
  });

  Future<void> chooseFolder() => harness.preferences.setBackupFolder(
    uri: 'content://tree/drive',
    name: 'Drive',
    key: 'A' * 43 + '=',
  );

  test('nothing happens until a folder is chosen', () async {
    await harness.services.captureText('a note');
    expect(await harness.services.backupToFolderIfDue(), isFalse);
    expect(folder.copies, isEmpty);
  });

  test('an empty library waits for its first note', () async {
    await chooseFolder();
    expect(await harness.services.backupToFolderIfDue(), isFalse);
    expect(folder.copies, isEmpty);
  });

  test(
    'once a day, as a named complete backup, leaving no file behind',
    () async {
      await chooseFolder();
      await harness.services.captureText('a note');
      expect(await harness.services.backupToFolderIfDue(), isTrue);
      expect(folder.copies, hasLength(1));
      expect(
        folder.copies.single,
        matches(RegExp(r'^Nex-auto-\d{4}-\d\d-\d\d-\d{6}\.nexfull$')),
      );
      expect(harness.preferences.backupFolderLastAt, isNotNull);
      expect(
        Directory('${harness.root.path}/cache')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.nexfull')),
        isEmpty,
        reason: 'the local copy is deleted once it is in the folder',
      );

      // Not again the same day, unless asked.
      expect(await harness.services.backupToFolderIfDue(), isFalse);
      expect(await harness.services.backupToFolderIfDue(force: true), isTrue);
      expect(folder.copies, hasLength(2));
    },
  );

  test('a folder that went away is a failure Settings can show', () async {
    await chooseFolder();
    await harness.services.captureText('a note');
    folder.reachableNow = false;
    expect(await harness.services.backupToFolderIfDue(), isFalse);
    expect(harness.preferences.backupFolderFailedAt, isNotNull);
    expect(harness.preferences.backupFolderFailure, 'access');

    folder
      ..reachableNow = true
      ..copyWorks = false;
    expect(await harness.services.backupToFolderIfDue(), isFalse);
    expect(harness.preferences.backupFolderLastAt, isNull);
    // The reason is kept, in the device's own words, for Settings to show.
    expect(harness.preferences.backupFolderFailure, 'write:write: IOException');

    folder.copyWorks = true;
    expect(await harness.services.backupToFolderIfDue(), isTrue);
    expect(harness.preferences.backupFolderFailedAt, isNull);
    expect(harness.preferences.backupFolderFailure, isNull);
  });

  test('the folder and its code stay on this phone', () async {
    await chooseFolder();
    final settings = harness.preferences.backupSettings();
    final keys = (settings['preferences'] as Map).keys;
    expect(keys.where((k) => '$k'.startsWith('backup_folder.')), isEmpty);
    expect(settings.toString(), isNot(contains('A' * 43)));
  });

  testWidgets('the section shows the folder and stopping clears it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(chooseFolder);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BackupScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Automatic copy to a folder'), findsOneWidget);
    expect(find.text('Drive · no copy yet'), findsOneWidget);

    await tester.tap(find.text('Stop copying'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Stop copying'), findsNWidgets(3));
    await tester.tap(find.widgetWithText(TextButton, 'Stop copying').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Drive · no copy yet'), findsNothing);
    expect(folder.released, ['content://tree/drive']);
    expect(harness.preferences.backupFolderUri, isNull);
  });

  test('backup file names sort by time', () {
    final a = nexAutoBackupName(DateTime.utc(2026, 9, 30, 9, 5, 1));
    final b = nexAutoBackupName(DateTime.utc(2026, 10, 1, 0, 0, 0));
    expect(a, 'Nex-auto-2026-09-30-090501.nexfull');
    expect(a.compareTo(b), lessThan(0));
  });
}
