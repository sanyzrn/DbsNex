import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/capture_sheet.dart';

import 'support/in_process_db.dart';

/// There is no Save button (ADR-002), so the first keystroke writes the note.
/// That write crosses the isolate boundary, and what happens to the keystrokes
/// typed while it is in the air is the whole of this file.
void main() {
  late Directory tmp;
  late InProcessDb db;
  late NexServices services;
  late NexPreferences preferences;
  final committed = <String>[];

  Future<void> boot({Duration? captureDelay}) async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_capture_draft_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    db = InProcessDb(
      dbPath: dbPath,
      deviceId: 'test',
      captureDelay: captureDelay,
    );
    preferences = await NexPreferences.load();
    services = NexServices.forTest(
      worker: db,
      deviceId: 'test',
      preferences: preferences,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
    committed.clear();
  }

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> showSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CaptureSheet(
            services: services,
            preferences: preferences,
            onVoice: () {},
            onCamera: () {},
            onGallery: () {},
            onFile: () {},
            onChecklist: () {},
            onLink: () {},
            onCommitted: committed.add,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('typing faster than the first write still makes one note', (
    tester,
  ) async {
    // Long enough that all three keystrokes below land inside it. In
    // production the same window is the isolate round trip, queued behind
    // whatever else the one-command-at-a-time worker is doing.
    await boot(captureDelay: const Duration(milliseconds: 400));
    await showSheet(tester);

    final field = find.byType(TextField);
    // `enterText` pumps a zero-duration frame, which does not advance the
    // gate — so these three all reach `changed()` with no id yet, which is
    // exactly the race. Before the fix each one started its own capture and
    // the library ended up with "h", "he" and the full line.
    await tester.enterText(field, 'h');
    await tester.enterText(field, 'he');
    await tester.enterText(field, 'hello from the race');

    await tester.pumpAndSettle(const Duration(seconds: 1));

    final notes = await db.timeline(limit: 50);
    expect(notes, hasLength(1), reason: 'one note, not one per keystroke');
    // And it says what was actually typed. The keystrokes that skipped the
    // debounce still have to reach the note once the id exists — otherwise
    // this stops being a duplicate bug and starts being a data-loss one.
    expect(notes.single.content, 'hello from the race');

    // The receipt fires for the note that exists, once. It used to fire per
    // draft, flashing on notes that were about to be orphaned.
    expect(committed, hasLength(1));
    expect(committed.single, notes.single.id);
  });

  testWidgets('clearing the field lets the next note start', (tester) async {
    // The regression the guard could have introduced. `flush` deletes the
    // note and nulls the id when the field goes empty; if the in-flight
    // marker were left behind, `changed` would read null-id-with-a-draft as
    // "still waiting" and never write anything again.
    await boot();
    await showSheet(tester);

    final field = find.byType(TextField);
    await tester.enterText(field, 'first');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(await db.timeline(limit: 50), hasLength(1));

    await tester.enterText(field, '');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(await db.timeline(limit: 50), isEmpty, reason: 'emptied, so gone');

    await tester.enterText(field, 'second');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final notes = await db.timeline(limit: 50);
    expect(notes, hasLength(1));
    expect(notes.single.content, 'second');
  });

  testWidgets('a slow first write still gets the rest of the sentence', (
    tester,
  ) async {
    // The narrower version of case one: type, wait past the 300ms debounce
    // with the write still in flight, and stop. Nothing else will call
    // `flush`, so if the draft does not reconcile when it lands, the note
    // keeps the first keystroke and the rest is lost with no error anywhere.
    await boot(captureDelay: const Duration(milliseconds: 600));
    await showSheet(tester);

    final field = find.byType(TextField);
    await tester.enterText(field, 'o');
    await tester.enterText(field, 'once upon a time');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final notes = await db.timeline(limit: 50);
    expect(notes, hasLength(1));
    expect(notes.single.content, 'once upon a time');
  });
}
