import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/about_screen.dart';

import 'support/in_process_db.dart';

/// flutter_test registers no plugin for `getApplicationSupportDirectory`,
/// which NexCrashLog.open() calls — without this, tapping "Share
/// diagnostics" would hit a real platform channel that does not exist here.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory tmp;
  late NexServices services;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_about_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tmp.path);
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets(
    'offers to share diagnostics, and says so when there are none yet',
    (tester) async {
      // The privacy section sits below the fold on the default test surface,
      // and a ListView only mounts what is within (or near) its viewport.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AboutScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Share diagnostics'), findsOneWidget);

      // No crash has happened in this run, so there is nothing to hand to the
      // share sheet — this is the branch that says so rather than opening it
      // on an empty file.
      await tester.tap(find.text('Share diagnostics'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing to share yet'), findsOneWidget);
    },
  );
}
