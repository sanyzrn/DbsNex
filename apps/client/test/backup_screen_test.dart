import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:nex_data/nex_data.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/backup_screen.dart';

import 'support/nex_harness.dart';

class _RescuePaths extends PathProviderPlatform {
  _RescuePaths(this.root);
  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// A local backup with nothing offered but Restore used to be a one-way
/// accumulation: nothing on this screen could ever remove one.
void main() {
  late NexTestHarness harness;
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_backup_',
      onboarded: false,
    );
    services = harness.services;
    preferences = harness.preferences;
    tmp = harness.root;
    preferences = await NexPreferences.load();
  });

  tearDown(() => harness.dispose());

  test('rescue export and restore preserve a library with missing media and its safety point', () async {
    final previousPaths = PathProviderPlatform.instance;
    final cache = Directory(p.join(tmp.path, 'cache'))..createSync();
    PathProviderPlatform.instance = _RescuePaths(cache.path);
    addTearDown(() => PathProviderPlatform.instance = previousPaths);
    final note = (await services.captureText('recoverable text'))!;
    final database = NexDatabase.open(services.dbPath);
    try {
      SqliteNoteRepository(database).insert(
        Note(
          id: 'lost-photo',
          type: NoteType.photo,
          mediaUri: p.join(services.mediaDir, 'lost.jpg'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          deviceId: 'test',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );
    } finally {
      database.close();
    }
    await expectLater(services.backupNow(), throwsStateError);
    final rescued = await services.exportRescueBackup();
    expect(rescued.missing, ['lost.jpg']);
    final result = await services.restoreBackup(File(rescued.path));
    expect(result.error, isNull);
    final restored = NexDatabase.open(services.dbPath);
    try {
      expect(
        SqliteNoteRepository(restored).getById(note.id)!.content,
        'recoverable text',
      );
    } finally {
      restored.close();
    }
    final safety = Directory(p.join(services.backupDir, 'before-restore'))
        .listSync()
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('.nexbak'));
    expect(NexBackupArchive.missingMedia(safety.path), ['lost.jpg']);
  });
  test(
    'an invalid backup is rejected with the original session still usable',
    () async {
      final note = (await services.captureText('keep this note'))!;
      final invalid = File(p.join(tmp.path, 'invalid.nexbak'))
        ..writeAsStringSync('not a backup');
      await expectLater(services.restoreBackup(invalid), throwsStateError);
      expect((await services.getById(note.id))!.content, 'keep this note');
      expect(await services.captureText('still writable'), isNotNull);
      expect(await services.listBackups(), isEmpty);
    },
  );

  test('failure after closing requests a restart and retains the original library plus a safety copy', () async {
    final note = (await services.captureText('backed-up note'))!;
    final photo = File(p.join(services.mediaDir, 'photo.jpg'))
      ..writeAsBytesSync([1, 2, 3]);
    await harness.db.capturePhoto(mediaUri: photo.path);
    await services.backupNow();
    final selected = (await services.listBackups()).single;
    await services.updateNote(note.id, 'keep this newer note');
    // Header/database preflight succeeds; materializing the staged media
    // fails after closing the worker because this compact blob was lost.
    Directory(p.join(services.backupDir, '.media')).deleteSync(recursive: true);
    final result = await services.restoreBackup(selected);
    expect(result.error, isNotNull);
    final reopened = NexDatabase.open(services.dbPath);
    try {
      expect(
        SqliteNoteRepository(reopened).getById(note.id)?.content,
        'keep this newer note',
      );
    } finally {
      reopened.close();
    }
    expect(
      Directory(p.join(services.backupDir, 'before-restore'))
          .listSync()
          .where((f) => f.path.endsWith('.nexbak')),
      hasLength(1),
    );
    expect(
      await services.listBackups(),
      hasLength(2),
      reason: 'The recovery copy must be visible and selectable in Backups.',
    );
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

  test('restoring the oldest safety copy survives retention pruning', () async {
    final note = (await services.captureText('oldest saved text'))!;
    final safety = p.join(services.backupDir, 'before-restore');
    await services.worker.backup(safety, mediaDir: services.mediaDir);
    final oldest = Directory(safety).listSync().whereType<File>().single;
    await services.updateNote(note.id, 'newer text');
    for (var i = 1; i < NexDatabase.backupRetention; i++) {
      await services.worker.backup(safety, mediaDir: services.mediaDir);
    }
    final result = await services.restoreBackup(oldest);
    expect(result.error, isNull);
    final reopened = NexDatabase.open(services.dbPath);
    try {
      expect(
        SqliteNoteRepository(reopened).getById(note.id)!.content,
        'oldest saved text',
      );
    } finally {
      reopened.close();
    }
  });

  testWidgets('a local backup can be deleted, with confirmation', (
    tester,
  ) async {
    // Room for the whole page: a ListView only mounts what is within (or
    // near) its viewport.
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

    // A restore point opens its own sheet: restore, share, or delete.
    Future<void> openDelete() async {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete backup'));
      await tester.pumpAndSettle();
    }

    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    await openDelete();

    // A confirmation, not an immediate delete — the file cannot come back.
    expect(find.bySubtype<AlertDialog>(), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await services.listBackups(), hasLength(1));

    await openDelete();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    // Deleting the manifest now also collects unreferenced blobs in an isolate.
    // Let actual I/O finish; advancing the widget clock cannot complete it.
    for (
      var attempt = 0;
      attempt < 100 &&
          (find.byIcon(Icons.more_horiz).evaluate().isNotEmpty ||
              find.byType(LinearProgressIndicator).evaluate().isNotEmpty);
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(await services.listBackups(), isEmpty);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.text('No backup yet'), findsOneWidget);
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
