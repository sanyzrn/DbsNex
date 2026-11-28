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
import 'package:nex_client/widgets/reminder_wheel.dart';

import 'support/in_process_db.dart';
import 'support/text_input.dart';

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

  Future<void> showSheet(
    WidgetTester tester, {
    VoidCallback? onFile,
    CaptureKind initialKind = CaptureKind.note,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CaptureSheet(
            services: services,
            preferences: preferences,
            onCamera: () {},
            onGallery: () {},
            onFile: onFile ?? () {},
            initialKind: initialKind,
            onCommitted: committed.add,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('media handoff stays open when the text write fails', (
    tester,
  ) async {
    await boot();
    var launched = 0;
    await showSheet(tester, onFile: () => launched++);
    await enterNexText(tester, nexInputs(), 'saved');
    await tester.pumpAndSettle();
    await enterNexText(tester, nexInputs(), 'saved and newer words');
    db.failUpdates = 10;
    await tester.tap(find.byIcon(Icons.insert_drive_file_outlined));
    await tester.pumpAndSettle();
    expect(launched, 0);
    expect(find.byType(CaptureSheet), findsOneWidget);
    expect((await db.timeline()).single.content, 'saved');
    db.failUpdates = 0;
    await tester.tap(find.byIcon(Icons.insert_drive_file_outlined));
    await tester.pumpAndSettle();
    expect(launched, 1);
    expect((await db.timeline()).single.content, 'saved and newer words');
  });

  testWidgets('closing before first insert preserves the entire draft', (
    tester,
  ) async {
    await boot(captureDelay: const Duration(milliseconds: 600));
    await showSheet(tester);
    await enterNexText(tester, nexInputs(), 'f');
    await enterNexText(tester, nexInputs(), 'full sentence before closing');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(
      (await db.timeline()).single.content,
      'full sentence before closing',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a whitespace-only code draft does not block a file handoff', (
    tester,
  ) async {
    await boot();
    var launched = 0;
    await showSheet(
      tester,
      initialKind: CaptureKind.code,
      onFile: () => launched++,
    );
    final field = nexInputs();
    await enterNexText(tester, field, 'void main() {}');
    await tester.pumpAndSettle();
    expect(await db.timeline(), hasLength(1));

    await enterNexText(tester, field, '  \n  ');
    await tester.tap(find.byIcon(Icons.insert_drive_file_outlined));
    await tester.pumpAndSettle();
    expect(await db.timeline(), isEmpty);
    expect(launched, 1);
  });

  test(
    'startup recovers a journal after an uncertain first commit exactly once',
    () async {
      await boot();
      final note = await services.captureDraft('interrupted', 'f');
      await services.captureJournal.write(
        'interrupted',
        'full recovered sentence',
      );
      await services.recoverCaptureDrafts();
      await services.recoverCaptureDrafts();
      final notes = await db.timeline();
      expect(notes, hasLength(1));
      expect(notes.single.id, note!.id);
      expect(notes.single.content, 'full recovered sentence');
      expect(services.captureJournal.pending(), isEmpty);
    },
  );

  test(
    'a journal older than the note does not wind it back (DATA-05)',
    () async {
      // The journal's last write failed while the database's succeeded, then
      // the process died: the note is newer than the journal.
      await boot();
      final note = await services.captureDraft('stale', 'first words');
      await services.captureJournal.write('stale', 'first words');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.updateNote(note!.id, 'first words and the rest');

      await services.recoverCaptureDrafts();

      expect((await db.timeline()).single.content, 'first words and the rest');
      expect(services.captureJournal.pending(), isEmpty);
    },
  );

  test('a failed recovery retains the journal for another launch', () async {
    await boot();
    await services.captureDraft('retry', 'old');
    await services.captureJournal.write('retry', 'new');
    db.failUpdates = 1;
    await services.recoverCaptureDrafts();
    expect(services.captureJournal.pending().single.text, 'new');
    await services.recoverCaptureDrafts();
    expect((await db.timeline()).single.content, 'new');
    expect(services.captureJournal.pending(), isEmpty);
  });

  test(
    'startup does not recover a whitespace-only journal into a note',
    () async {
      // In the sheet, whitespace is emptiness with a card attached: the
      // note is retired, not kept. A journal the process died holding at
      // whitespace used to come back as a note of blank lines.
      await boot();
      await services.captureDraft('ws', 'words');
      await services.captureJournal.write('ws', '   ');
      await services.recoverCaptureDrafts();
      expect(await db.timeline(), isEmpty);
      expect(services.captureJournal.pending(), isEmpty);
    },
  );

  testWidgets('a keystroke flush reads neither the note nor the timeline', (
    tester,
  ) async {
    // While the sheet is open, each debounced burst of typing used to
    // cost a note read (to re-bake a reminder most notes do not have)
    // and a full timeline window read — per pause in the typing, none of
    // it visible under the sheet. The flush now writes the words and
    // nothing else; the closing sheet refreshes once.
    await boot();
    await showSheet(tester);
    final reads = db.timelineReads;

    final field = nexInputs();
    await enterNexText(tester, field, 'first');
    await tester.pumpAndSettle(const Duration(milliseconds: 700));
    await enterNexText(tester, field, 'first, and more');
    await tester.pumpAndSettle(const Duration(milliseconds: 700));

    expect(db.timelineReads, reads);
    expect((await db.timeline(limit: 50)).single.content, 'first, and more');
  });

  testWidgets(
    'clearing and closing before first insert leaves no partial note',
    (tester) async {
      await boot(captureDelay: const Duration(milliseconds: 600));
      await showSheet(tester);
      await enterNexText(tester, nexInputs(), 'draft');
      await enterNexText(tester, nexInputs(), '');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(await db.timeline(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('typing faster than the first write still makes one note', (
    tester,
  ) async {
    // Long enough that all three keystrokes below land inside it. In
    // production the same window is the isolate round trip, queued behind
    // whatever else the one-command-at-a-time worker is doing.
    await boot(captureDelay: const Duration(milliseconds: 400));
    await showSheet(tester);

    final field = nexInputs();
    // `enterText` pumps a zero-duration frame, which does not advance the
    // gate — so these three all reach `changed()` with no id yet, which is
    // exactly the race. Before the fix each one started its own capture and
    // the library ended up with "h", "he" and the full line.
    await enterNexText(tester, field, 'h');
    await enterNexText(tester, field, 'he');
    await enterNexText(tester, field, 'hello from the race');

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

    final field = nexInputs();
    await enterNexText(tester, field, 'first');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(await db.timeline(limit: 50), hasLength(1));

    await enterNexText(tester, field, '');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(await db.timeline(limit: 50), isEmpty, reason: 'emptied, so gone');

    await enterNexText(tester, field, 'second');
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

    final field = nexInputs();
    await enterNexText(tester, field, 'o');
    await enterNexText(tester, field, 'once upon a time');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final notes = await db.timeline(limit: 50);
    expect(notes, hasLength(1));
    expect(notes.single.content, 'once upon a time');
  });
  testWidgets(
    'a language change that could not be saved keeps the sheet open',
    (tester) async {
      // The words did not change, only the fence around them. Closing used to
      // compare the two texts alone, so a failed language write closed the
      // sheet over a note still saved in the old language.
      await boot();
      await showSheet(tester, initialKind: CaptureKind.code);
      final field = nexInputs();
      await enterNexText(tester, field, 'void main() {}');
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      const detected = '```dart\nvoid main() {}\n```';
      const changed = '```python\nvoid main() {}\n```';
      expect((await db.timeline()).single.content, detected);

      // Pick a different language from the one detected on paste. Both
      // writes fail: the picker starts one and closing retries it.
      db.failUpdates = 2;
      await tester.tap(find.byKey(const ValueKey('capture-code-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Python'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(
        (await db.timeline()).single.content,
        detected,
        reason: 'the refused write must really have been refused',
      );

      await tester.tap(find.byKey(const ValueKey('capture-send')));
      await tester.pumpAndSettle();
      expect(
        find.byType(CaptureSheet),
        findsOneWidget,
        reason: 'closing over a fence that never landed loses the language',
      );

      db.failUpdates = 0;
      await tester.tap(find.byKey(const ValueKey('capture-send')));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureSheet), findsNothing);
      expect((await db.timeline()).single.content, changed);
    },
  );

  testWidgets(
    'a reminder is still on the note after the retry once the sheet is gone',
    (tester) async {
      // The write after unmount used to retry without the reminder flag, so the
      // notification kept the words from before the last edit.
      await boot();
      await showSheet(tester);
      final field = nexInputs();
      await enterNexText(tester, field, 'pick up the ring');
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      final note = (await db.timeline()).single;
      await db.setDueAt(
        note.id,
        DateTime.now().add(const Duration(hours: 2)).toUtc(),
      );
      await tester.tap(find.byKey(const ValueKey('capture-remind')));
      await tester.pumpAndSettle();
      expect(find.byType(ReminderWheel), findsOneWidget);
      // Dismissed without changing the time: [_remind] reads the note back and
      // learns from the note itself that it has a reminder.
      Navigator.of(tester.element(find.byType(ReminderWheel))).pop();
      await tester.pumpAndSettle();
      final alarm = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('capture-remind')),
          matching: find.byType(Icon),
        ),
      );
      expect(alarm.icon, Icons.alarm_on);

      db.failUpdates = 1;
      final reads = db.noteReads;
      await enterNexText(tester, field, 'pick up the ring today');
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect((await db.timeline()).single.content, 'pick up the ring');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      final saved = (await db.timeline()).single;
      expect(saved.content, 'pick up the ring today');
      expect(saved.dueAt, isNotNull, reason: 'the reminder outlives the sheet');
      expect(
        db.noteReads,
        reads + 1,
        reason:
            'the retry re-reads the note to re-arm its notification with the '
            'new words; without the flag it writes the text and nothing else',
      );
    },
  );

  testWidgets('an edit that failed to save is written again on close', (
    tester,
  ) async {
    // Found by an independent audit. `flush` sent the update and marked the
    // text as persisted in the same breath, without waiting to hear whether
    // the write landed. When it did not, every later flush compared the
    // field with a "persisted" value it had never actually reached, found
    // them equal, and did nothing — so the sheet closed over text that was
    // not in the library, and the error was nobody's.
    await boot();
    await showSheet(tester);

    final field = nexInputs();
    await enterNexText(tester, field, 'first');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    db.failUpdates = 1;
    await enterNexText(tester, field, 'first, then more');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(
      (await db.timeline(limit: 50)).single.content,
      'first',
      reason: 'the refused write must really have been refused',
    );

    // Closing the sheet flushes. Before the fix it saw nothing to do.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect((await db.timeline(limit: 50)).single.content, 'first, then more');
  });
}
