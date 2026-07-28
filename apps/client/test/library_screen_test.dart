import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/library_screen.dart';
import 'package:nex_client/screens/recently_deleted_screen.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_client/screens/tag_manager_screen.dart';

import 'support/in_process_db.dart';

/// Settings holds preferences. Content lives somewhere a person would look for
/// content.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_library_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    Directory(p.join(tmp.path, 'media')).createSync(recursive: true);
    Directory(p.join(tmp.path, 'backups')).createSync(recursive: true);
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: p.join(tmp.path, 'media'),
      backupDir: p.join(tmp.path, 'backups'),
    );
    preferences = await NexPreferences.load();
    // The storage figure is measured by walking directories, which is real
    // async I/O and so never resolves inside flutter_test's fake-async zone —
    // its skeleton stays up for the whole test. A repeating shimmer means
    // `pumpAndSettle` can never settle, so motion is turned off, which the app
    // ORs into MediaQuery and NexSkeleton honours by stopping outright.
    await preferences.setReduceMotion(true);
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('Trash and Tags are one tap from the timeline', (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);

    // A note deleted by an accidental swipe has to be recoverable without
    // reasoning your way to a gear icon.
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    expect(find.byType(RecentlyDeletedScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.byType(TagManagerScreen), findsOneWidget);
  });

  testWidgets('Settings no longer holds anything containing notes',
      (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final sheet = find.byType(SettingsSheet);
    expect(sheet, findsOneWidget);
    for (final row in ['Tags', 'Trash', 'Storage']) {
      expect(
        find.descendant(of: sheet, matching: find.text(row)),
        findsNothing,
        reason: '$row is content, not a preference',
      );
    }
    // What is left is preferences, and they are still there.
    expect(
      find.descendant(of: sheet, matching: find.text('Appearance')),
      findsOneWidget,
    );
  });
}
