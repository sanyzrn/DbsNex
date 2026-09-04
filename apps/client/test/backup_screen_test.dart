import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/backup_screen.dart';

import 'support/in_process_db.dart';

/// A local backup with nothing offered but Restore used to be a one-way
/// accumulation: nothing on this screen could ever remove one.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_backup_');
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
    preferences = await NexPreferences.load();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a brand-new install does not back up an empty library', () async {
    // Reported as "there is already a backup on a fresh install". There was:
    // the throttle is due the first time it is ever asked, so five seconds
    // after a first launch the app wrote a backup of a database with nothing
    // in it, and Settings then said "1 backup" to someone who had not written
    // a single note.
    expect(await services.backupIfDue(), isFalse);
    expect(await services.listBackups(), isEmpty);

    // And the clock is not marked by that refusal, so the first real note is
    // backed up immediately rather than twelve hours after launch.
    await services.captureText('the first thought');
    expect(await services.backupIfDue(), isTrue);
    expect(await services.listBackups(), hasLength(1));

    // Still throttled after that — one note is not a reason to back up twice.
    expect(await services.backupIfDue(), isFalse);
    expect(await services.listBackups(), hasLength(1));
  });

  testWidgets('a local backup can be deleted, with confirmation', (
    tester,
  ) async {
    // The export/import explanations above the backup list are tall enough
    // that the row is below the fold on the default test surface — and a
    // ListView only mounts what is within (or near) its viewport, so the
    // delete button would not exist in the tree at all without the room to
    // show it.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await services.backupNow();
    expect(await services.listBackups(), hasLength(1));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BackupScreen(services: services, preferences: preferences),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // A confirmation, not an immediate delete — the file cannot come back.
    expect(find.text('Delete backup'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await services.listBackups(), hasLength(1));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(await services.listBackups(), isEmpty);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  group('the reason a failure gives the person reading the banner', () {
    // Every one of these banners used to be the same sentence — "The
    // operation failed" — raised by five different things, each of which
    // discarded the exception. The banner is transient, so by the time you
    // wonder what it meant it is gone. The reason is now appended to it.
    test('an exception is flattened onto one line', () {
      final message = NexServices.describeFailure(
        Exception('connection closed\n  at the second attempt'),
      );
      expect(message, isNot(contains('\n')));
      expect(message, contains('connection closed'));
      expect(message, contains('at the second attempt'));
    });

    test('a long reason is cut rather than allowed to fill the screen', () {
      final message = NexServices.describeFailure(StateError('x' * 500));
      // A banner is one or two lines. Anything longer pushes the app off
      // screen, and the untruncated text is in the diagnostics file anyway.
      expect(message.length, lessThanOrEqualTo(120));
      expect(message, endsWith('\u2026'));
    });

    test('a reason that already fits is left exactly as it is', () {
      final message = NexServices.describeFailure(StateError('short'));
      expect(message, contains('short'));
      expect(message, isNot(endsWith('\u2026')));
    });
  });
}
