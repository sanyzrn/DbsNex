import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/os_capture_bridge.dart';
import 'package:nex_client/screens/intelligence_screen.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_client/widgets/choice_cards.dart';
import 'package:nex_client/widgets/tag_color_picker.dart';

import 'support/in_process_db.dart';

/// Builds the real service graph against an in-process database.
///
/// Not a NexDbWorker: flutter_test runs test bodies in a fake-async zone where
/// isolate port traffic never resolves, so awaiting a worker reply hangs. The
/// storage stack underneath is the same one the worker drives.
Future<NexServices> _testServices(Directory tmp) async {
  final dbPath = p.join(tmp.path, 'nex.sqlite');
  final mediaDir = p.join(tmp.path, 'media');
  final backupDir = p.join(tmp.path, 'backups');
  Directory(mediaDir).createSync(recursive: true);
  Directory(backupDir).createSync(recursive: true);
  final worker = InProcessDb(dbPath: dbPath, deviceId: 'test');
  testWorker = worker;
  return NexServices.forTest(
    worker: worker,
    deviceId: 'test',
    preferences: await NexPreferences.load(),
    backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
    dbPath: dbPath,
    mediaDir: mediaDir,
    backupDir: backupDir,
  );
}

/// The in-process database behind [_testServices], for the few tests that have
/// to reach past the service layer.
late InProcessDb testWorker;

void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_client_');
    services = await _testServices(tmp);
    preferences = await NexPreferences.load();
    // Every one of these tests starts from an empty preference store, which
    // is exactly what a first-ever launch looks like — so without this they
    // would all open on the onboarding screen instead of the timeline.
    // Onboarding has its own test file.
    await preferences.completeOnboarding();
    // And the walk-through that follows it, for the same reason: it opens
    // over the timeline's own controls, so without this every tap in this
    // file would land on its scrim.
    await preferences.completeTour();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('Timeline shows tag filter chip row with All', (tester) async {
    final note = (await services.captureText('tagged'))!;
    await services.addTag(noteId: note.id, name: 'Work', color: '#F0A93B');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    // Both the tag row and the content-type row carry an "All" chip, so the
    // finder has to say which row it means.
    expect(
      find.descendant(
        of: find.byType(TagFilterRow),
        matching: find.text('All'),
      ),
      findsOneWidget,
    );
    expect(find.text('Work'), findsWidgets);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('Content-type filter narrows the timeline to one type (FR-4.5)', (
    tester,
  ) async {
    await services.captureText('a written thought');
    await services.captureVoice(
      mediaUri: p.join(tmp.path, 'media', 'clip.m4a'),
      mediaHash: sha256OfBytes(Uint8List.fromList([9, 9, 9])),
      durationMs: 1500,
    );
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.text('a written thought'), findsOneWidget);

    // The content-type filter lives behind the filter row's leading icon
    // button, as in the mockup, so it takes a tap to reach.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    expect(find.text('a written thought'), findsNothing);
  });

  testWidgets('the filter can narrow to notes with a reminder ahead', (
    tester,
  ) async {
    // A state, not a type — which is why it sits under a line in that sheet
    // rather than in the run of note kinds above it, and why it layers on
    // whichever kind is chosen instead of replacing it.
    await services.captureText('call the dentist');
    await services.captureText('a passing thought');
    final dentist = (await services.worker.timeline()).firstWhere(
      (note) => note.content == 'call the dentist',
    );
    await services.setDueAt(
      dentist.id,
      DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    await services.refreshTimeline();

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.text('a passing thought'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Has a reminder'));
    await tester.pumpAndSettle();

    expect(find.text('call the dentist'), findsOneWidget);
    expect(find.text('a passing thought'), findsNothing);

    // And off again from the same row, which is the whole of its state.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Has a reminder'));
    await tester.pumpAndSettle();

    expect(find.text('a passing thought'), findsOneWidget);
  });

  testWidgets('Timeline is home with capture FAB and no Save button', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    // The app bar carries the mark rather than a text title now — the
    // greeting it used to share the bar with is a header in the list below.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets(
    'Capture sheet focuses text with Voice/Camera/Gallery/File inline',
    (tester) async {
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      // Text is the default mode — a focused field, not a menu tile.
      expect(find.byType(TextField), findsWidgets);
      // Icon-only: the name survives as a tooltip, not as printed text.
      expect(find.byTooltip('Voice'), findsOneWidget);
      expect(find.byTooltip('Camera'), findsOneWidget);
      expect(find.byTooltip('Gallery'), findsOneWidget);
      expect(find.byTooltip('File'), findsOneWidget);
      // Not a type-picker-first menu of four equal choices.
      expect(find.text('Text'), findsNothing);
      expect(find.text('Save'), findsNothing);
    },
  );

  testWidgets(
    'the reminder button is not on an empty capture sheet, only on a written one',
    (tester) async {
      // The one hard rule over this sheet is that nothing on the way in may
      // become a decision, and a date picker is the most expensive decision
      // there is. So it is absent until there is something to be reminded
      // about — and by then the note has already been saved by the first
      // keystroke, so the button hangs a time on a note that exists rather
      // than gating one that does not.
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Remind'), findsNothing);

      final captureField = find.descendant(
        of: find.byType(CaptureSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(captureField, 'put the bins out');
      await tester.pump();

      expect(find.byTooltip('Remind'), findsOneWidget);
      // Still no Save button, and still nothing standing between the words
      // and the timeline.
      expect(find.text('Save'), findsNothing);

      // Emptied again, it goes with the note it belonged to.
      await tester.enterText(captureField, '');
      await tester.pump();
      expect(find.byTooltip('Remind'), findsNothing);

      // The sheet debounces its writes; let the pending one run rather than
      // leaving a timer alive past the end of the test.
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'Enter submits the first capture by default; Shift+Enter still breaks a line',
    (tester) async {
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // The timeline's own search field is a TextField too, and it never
      // leaves the tree — scope to the capture sheet's field specifically.
      final captureField = find.descendant(
        of: find.byType(CaptureSheet),
        matching: find.byType(TextField),
      );

      await tester.enterText(captureField, 'first line');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      // Shift+Enter is the escape hatch: our handler must not treat it as
      // submit, leaving the field's own newline handling free to act.
      expect(
        captureField,
        findsOneWidget,
        reason: 'Shift+Enter must not submit',
      );
      expect(find.byType(CaptureSheet), findsOneWidget);

      await tester.enterText(captureField, 'first line\nsecond line');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Plain Enter submitted and closed the sheet.
      expect(find.byType(CaptureSheet), findsNothing);
      final notes = await services.timeline(limit: 5);
      expect(notes.first.content, 'first line\nsecond line');
    },
  );

  testWidgets(
    'a long paste keeps the submit button on screen instead of pushing it off',
    (tester) async {
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final captureField = find.descendant(
        of: find.byType(CaptureSheet),
        matching: find.byType(TextField),
      );
      // A field left unbounded (`maxLines: null` with nothing capping its
      // height) grows with every line pasted in, and used to push the
      // submit button below the bottom of the sheet entirely.
      await tester.enterText(
        captureField,
        List.filled(60, 'a line').join('\n'),
      );
      await tester.pump();

      // The FAB behind the sheet also has tooltip "Capture" — scope to the
      // sheet's own submit button specifically.
      final submit = find.descendant(
        of: find.byType(CaptureSheet),
        matching: find.byTooltip('Capture'),
      );
      expect(submit, findsOneWidget);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(
        tester.getBottomRight(submit).dy,
        lessThanOrEqualTo(screenHeight),
        reason: 'the submit button must stay within the visible screen',
      );

      // Still reachable, not just present in the tree.
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureSheet), findsNothing);
    },
  );

  testWidgets('turning off "Enter saves" lets Enter break a line instead', (
    tester,
  ) async {
    await preferences.setEnterSubmitsCapture(false);
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final captureField = find.descendant(
      of: find.byType(CaptureSheet),
      matching: find.byType(TextField),
    );

    await tester.enterText(captureField, 'a line');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    // The preference is off, so our handler ignores Enter entirely —
    // it never submits, whatever the field itself then does with it.
    expect(find.byType(CaptureSheet), findsOneWidget, reason: 'still open');
  });

  testWidgets('Capture FAB is centered and large (~64px)', (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab, isNotNull);
    final box = tester.renderObject<RenderBox>(
      find.byType(FloatingActionButton),
    );
    expect(box.size.width, closeTo(nexCaptureFabSize, 1));
    expect(box.size.height, closeTo(nexCaptureFabSize, 1));
    // The Scaffold that actually owns the FAB — TimelineScreen's own, not the
    // bare one the app shell wraps the Navigator in so toasts can paint above
    // dialogs (see NexApp.builder).
    final scaffold = tester.widget<Scaffold>(
      find
          .descendant(
            of: find.byType(TimelineScreen),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(
      scaffold.floatingActionButtonLocation,
      FloatingActionButtonLocation.centerFloat,
    );
  });

  test('OS share-intent text auto-saves with zero fields', () async {
    final bridge = OsCaptureBridge(services);
    await bridge.handle({
      'type': 'shared_text',
      'text': 'shared from another app',
    });
    expect(
      (await services.timeline()).first.content,
      'shared from another app',
    );
  });

  test('OS share-intent photo auto-saves with media_hash', () async {
    final src = File(p.join(services.mediaDir, 'in.jpg'))
      ..writeAsBytesSync([1, 2, 3, 4, 5]);
    final bridge = OsCaptureBridge(services);
    await bridge.handle({'type': 'shared_photo', 'path': src.path});
    final note = (await services.timeline()).first;
    expect(note.type, NoteType.photo);
    expect(note.mediaHash, isNotNull);
  });

  test('OS share-intent file preserves original filename and MIME', () async {
    final src = File(p.join(services.mediaDir, 'cache-placeholder.bin'))
      ..writeAsBytesSync([9, 8, 7, 6]);
    final bridge = OsCaptureBridge(services);
    await bridge.handle({
      'type': 'shared_file',
      'path': src.path,
      'filename': 'Quarterly-Report.pdf',
      'mimeType': 'application/pdf',
    });
    final note = (await services.timeline()).first;
    expect(note.type, NoteType.file);
    expect(note.content, 'Quarterly-Report.pdf');
    expect(note.mimeType, 'application/pdf');
    expect(note.content, isNot(contains('.bin')));
  });

  test(
    'Optional caption on media notes is distinct from OCR/transcript',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final photo = await services.capturePhoto(
        mediaUri: p.join(services.mediaDir, 'p.jpg'),
        mediaHash: sha256OfBytes(bytes),
      );
      expect(photo.caption, isNull);
      await services.setCaption(photo.id, 'whiteboard from sync');
      final updated = (await services.getById(photo.id))!;
      expect(updated.caption, 'whiteboard from sync');
      expect(updated.ocrText, isNull);
    },
  );

  test(
    'a manual caption outranks the AI-derived text for display and copy',
    () async {
      // Reported symptom: the timeline card (and the detail sheet's main
      // copy button) kept showing the OCR/transcript read even after the
      // user wrote their own caption — the extracted text has its own small
      // copy icon in the AI panel, but it should not be what the card and
      // the primary copy action lead with once a caption exists.
      await preferences.setAiEnabled(true);
      services.applyAiPreferences(preferences);

      final bytes = Uint8List.fromList([1, 2, 3]);
      final photo = await services.capturePhoto(
        mediaUri: p.join(services.mediaDir, 'p.jpg'),
        mediaHash: sha256OfBytes(bytes),
      );
      await services.backfillEnrichment();
      final withOcr = (await services.getById(photo.id))!;
      // The on-device adapter cannot read images and no longer pretends to:
      // the OCR slot is marked attempted-empty rather than filled with a
      // fabricated reading, and the card shows nothing at all.
      expect(withOcr.ocrText, '');
      expect(withOcr.displayText, isNull, reason: 'nothing else to show yet');

      await services.setCaption(photo.id, 'the actual point of this photo');
      final captioned = (await services.getById(photo.id))!;
      expect(captioned.displayText, 'the actual point of this photo');
      expect(
        captioned.displayText,
        isNot(contains('photo text')),
        reason: 'the caption replaces the reading, not sits beside it',
      );
    },
  );

  test('Timeline tag filter returns only matching notes', () async {
    final a = (await services.captureText('alpha'))!;
    final b = (await services.captureText('beta'))!;
    await services.addTag(noteId: a.id, name: 'Work');
    await services.addTag(noteId: b.id, name: 'Idea');
    final work = (await services.listTags()).firstWhere(
      (t) => t.name == 'Work',
    );
    final filtered = await services.timeline(tagId: work.id);
    expect(filtered.map((n) => n.id), [a.id]);
  });

  test(
    'Swipe mapping defaults, and each edge moves alone (ADR-022 revised)',
    () async {
      expect(preferences.leadingAction, SwipeAction.addTag);
      expect(preferences.trailingAction, SwipeAction.delete);
      // Setting one edge must leave the other exactly where it was: the old
      // swap coupled them, which is the behaviour this replaced.
      await preferences.setSwipeAction(
        isLeading: true,
        action: SwipeAction.delete,
      );
      expect(preferences.leadingAction, SwipeAction.delete);
      expect(preferences.trailingAction, SwipeAction.delete);
      await preferences.setSwipeAction(
        isLeading: false,
        action: SwipeAction.none,
      );
      expect(preferences.leadingAction, SwipeAction.delete);
      expect(preferences.trailingAction, SwipeAction.none);
    },
  );

  test('Comfort Mode defaults off and toggles (ADR-023)', () async {
    expect(preferences.comfortMode, isFalse);
    await preferences.setComfortMode(true);
    expect(preferences.comfortMode, isTrue);
  });

  test(
    'Glass and background appearance choices persist independently',
    () async {
      expect(preferences.liquidGlass, isFalse);
      expect(preferences.backgroundPattern, NexBackgroundPattern.plain);

      await preferences.setLiquidGlass(true);
      await preferences.setBackgroundPattern(NexBackgroundPattern.aurora);

      expect(preferences.liquidGlass, isTrue);
      expect(preferences.backgroundPattern, NexBackgroundPattern.aurora);
      expect(preferences.themeMode, ThemeMode.system);
    },
  );

  test('UI scale defaults to 1.0 and persists a choice', () async {
    expect(preferences.uiScale, 1.0);
    await preferences.setUiScale(1.3);
    expect(preferences.uiScale, 1.3);
  });

  testWidgets('the UI scale preference actually reaches the text scaler', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    final before = MediaQuery.of(
      tester.element(find.byType(Scaffold).first),
    ).textScaler;

    await preferences.setUiScale(1.3);
    await tester.pumpAndSettle();
    final after = MediaQuery.of(
      tester.element(find.byType(Scaffold).first),
    ).textScaler;

    expect(after.scale(100), greaterThan(before.scale(100)));
  });

  test('Theme mode defaults to System and can force Light/Dark', () async {
    expect(preferences.themeMode, ThemeMode.system);
    await preferences.setThemeMode(ThemeMode.dark);
    expect(preferences.themeMode, ThemeMode.dark);
    await preferences.setThemeMode(ThemeMode.light);
    expect(preferences.themeMode, ThemeMode.light);
  });

  test('File capture stores original filename for display', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
    final note = await services.captureFile(
      mediaUri: p.join(services.mediaDir, 'doc.pdf'),
      mediaHash: sha256OfBytes(bytes),
      originalFilename: 'Quarterly-Report.pdf',
    );
    expect(note.type, NoteType.file);
    expect(note.content, 'Quarterly-Report.pdf');
  });

  test('listBackups returns newest-first sqlite files', () async {
    final older = File(p.join(services.backupDir, 'nex-2020.sqlite'))
      ..writeAsBytesSync([1, 2, 3]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final newer = File(p.join(services.backupDir, 'nex-2021.sqlite'))
      ..writeAsBytesSync([1, 2, 3, 4]);
    // Touch mtimes via path sort (listBackups sorts by path desc).
    final listed = await services.listBackups();
    expect(
      listed.map((f) => p.basename(f.path)),
      containsAll(['nex-2020.sqlite', 'nex-2021.sqlite']),
    );
    expect(listed.first.path, newer.path);
    expect(older.existsSync(), isTrue);
  });

  test('Comfort Mode tokens keep WCAG AA contrast', () async {
    // Light comfort: #2E2A22 on #F7F1E6
    expect(
      nexContrastRatio(
        NexColors.textPrimaryLightComfort,
        NexColors.bgPrimaryLightComfort,
      ),
      greaterThanOrEqualTo(4.5),
    );
    // Dark comfort: #D9CFC0 on #17130F
    expect(
      nexContrastRatio(
        NexColors.textPrimaryDarkComfort,
        NexColors.bgPrimaryDarkComfort,
      ),
      greaterThanOrEqualTo(4.5),
    );
    // Non-comfort also AA
    expect(
      nexContrastRatio(NexColors.textPrimaryLight, NexColors.bgPrimaryLight),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      nexContrastRatio(NexColors.textPrimaryDark, NexColors.bgPrimaryDark),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('Soft-delete undo restores note', () async {
    final note = (await services.captureText('undo me'))!;
    await services.deleteNote(note.id);
    expect(await services.timeline(), isEmpty);
    await services.undelete(note.id);
    expect((await services.timeline()).single.content, 'undo me');
  });

  test('Offline: capture/search/tag use local SQLite only', () async {
    final note = (await services.captureText('offline'))!;
    await services.addTag(noteId: note.id, name: 'Work');
    final hits = await services.search(const SearchFilters(query: 'offline'));
    expect(hits, hasLength(1));
    expect(hits.first.tags.first.name, 'Work');
  });

  test(
    'Search budget: FTS under 200ms for 1000 notes (1.x.2 hardening)',
    () async {
      for (var i = 0; i < 1000; i++) {
        await services.captureText('note number $i with keywords alpha');
      }
      final sw = Stopwatch()..start();
      final hits = await services.search(const SearchFilters(query: 'alpha'));
      sw.stop();
      expect(hits.length, greaterThan(0));
      expect(sw.elapsedMilliseconds, lessThan(200));
    },
  );

  test('Durable write budget: text capture under 300ms', () async {
    final sw = Stopwatch()..start();
    await services.captureText('budget');
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(300));
  });

  test('Timeline page load under budget for large set', () async {
    for (var i = 0; i < 2000; i++) {
      await services.captureText('bulk $i');
    }
    final sw = Stopwatch()..start();
    final page = await services.timeline(limit: 50);
    sw.stop();
    expect(page, hasLength(50));
    expect(sw.elapsedMilliseconds, lessThan(200));
  });

  test(
    'loadMoreTimeline grows the timeline window past the first page',
    () async {
      // refreshTimeline's window used to be a hardcoded 200 with no way to
      // ask for more: past that count, older notes were not just off-screen,
      // nothing ever fetched them.
      final events = <List<Note>>[];
      final sub = services.timelineStream.listen(events.add);
      addTearDown(sub.cancel);

      for (var i = 0; i < 210; i++) {
        await services.captureText('bulk $i');
      }
      // The broadcast controller's `add` schedules delivery rather than
      // calling listeners inline, so each assertion needs a turn of the
      // event loop before `events` reflects it.
      await services.refreshTimeline();
      await Future<void>.delayed(Duration.zero);
      expect(events.last, hasLength(200));

      expect(await services.loadMoreTimeline(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(events.last, hasLength(210));

      // Nothing left past 210: the next ask comes back empty, and the window
      // is not reloaded a third time over it.
      expect(await services.loadMoreTimeline(), isFalse);
      expect(events.last, hasLength(210));
    },
  );

  test('Voice capture stores hash; keyword search excludes it', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final voice = await services.captureVoice(
      mediaUri: p.join(services.mediaDir, 'v.m4a'),
      mediaHash: sha256OfBytes(bytes),
      durationMs: 900,
    );
    expect(voice.mediaHash, isNotNull);
    expect(
      await services.search(const SearchFilters(query: 'anything')),
      isEmpty,
    );
  });

  test('AI preferences default on; cloud opt-in defaults off', () async {
    expect(preferences.aiCapabilities.transcription, isTrue);
    expect(preferences.cloudAiOptIn, isFalse);
  });

  test('scheduleEnrichment does not block capture budget', () async {
    final sw = Stopwatch()..start();
    final note = (await services.captureText('enrich later'))!;
    services.scheduleEnrichment(note.id);
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(300));
  });

  testWidgets('Intelligence is off by default and lives on its own screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // The sheet offers a way in, not a row of switches that quietly did
    // nothing because no provider stood behind them.
    expect(find.text('Transcription'), findsNothing);
    final intelligenceRow = find.ancestor(
      of: find.text('Transcription, summaries, tags'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: intelligenceRow, matching: find.text('Off')),
      findsOneWidget,
    );

    // The sheet scrolls; tapping a row below the fold lands on whatever is
    // actually at those coordinates.
    await tester.ensureVisible(find.text('Transcription, summaries, tags'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transcription, summaries, tags'));
    await tester.pumpAndSettle();

    // Off until asked: the offline promise holds until the user says otherwise.
    expect(preferences.aiEnabled, isFalse);
    expect(preferences.effectiveAiCapabilities.transcription, isFalse);
    // ...and the capability switches are not even shown while it is off.
    // Scoped to the screen: the settings sheet underneath it on the navigator
    // stack has switches of its own.
    expect(find.text('Transcription'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(IntelligenceScreen),
        matching: find.byType(NexSwitchTile),
      ),
      findsOneWidget,
    );
  });

  test('the master switch overrides every capability', () async {
    // The individual switches default on, so with AI off they would otherwise
    // report as enabled and the worker would act on them.
    expect(preferences.aiCapabilities.transcription, isTrue);
    expect(preferences.aiEnabled, isFalse);
    expect(preferences.effectiveAiCapabilities.transcription, isFalse);
    expect(preferences.effectiveAiCapabilities.summarization, isFalse);

    await preferences.setAiEnabled(true);
    expect(preferences.effectiveAiCapabilities.transcription, isTrue);
  });

  testWidgets('UI tokens apply bg-primary; Comfort swaps tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.scaffoldBackgroundColor, NexColors.bgPrimaryLight);

    await preferences.setComfortMode(true);
    await tester.pump();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.scaffoldBackgroundColor, NexColors.bgPrimaryLightComfort);
  });

  testWidgets('Settings lists one row per setting, values and all', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // The pickers are behind their rows now, so what the list shows is the
    // name of each setting and what it is currently set to. Nothing is
    // expanded: the cards that used to fill two and a half screens of scroll
    // before the first switch are not on screen at all.
    expect(find.text('Swipe actions'), findsOneWidget);
    expect(find.text('Comfort Mode'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Liquid Glass'), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Text & UI size'), findsOneWidget);
    expect(find.byType(NexChoiceCards<ThemeMode>), findsNothing);
    expect(find.byType(NexChoiceCards<double>), findsNothing);

    // The current value sits under each name — the whole reason a collapsed
    // row is not a step backwards from an expanded picker.
    expect(find.text('System'), findsWidgets);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('a settings row opens its picker, and the pick sticks', (
    tester,
  ) async {
    // Settings is a long list on a short test surface, and a scroll view
    // only mounts what is within reach.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(preferences.themeMode, ThemeMode.system);
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    // Same cards as before, previews and all — only where they live moved.
    expect(find.byType(NexChoiceCards<ThemeMode>), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(preferences.themeMode, ThemeMode.dark);
    // Closed on selection, and the row it came from now reads back the pick
    // rather than the value it opened with.
    expect(find.byType(NexChoiceCards<ThemeMode>), findsNothing);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Theme'),
        matching: find.text('Dark'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('background picker applies a built-in preset immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Background'));
    await tester.pumpAndSettle();
    expect(find.byType(NexChoiceCards<NexBackgroundPattern>), findsOneWidget);

    await tester.tap(find.text('Aurora'));
    await tester.pumpAndSettle();

    expect(preferences.backgroundPattern, NexBackgroundPattern.aurora);
    expect(find.byType(NexChoiceCards<NexBackgroundPattern>), findsNothing);
  });

  testWidgets('the AI output language is its own setting, not the app locale', (
    tester,
  ) async {
    // Settings is a long list on a short test surface, and a scroll view
    // only mounts what is within reach.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(preferences.aiOutputLanguage, AiOutputLanguage.auto);
    await tester.tap(find.text('AI output language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Persian'));
    await tester.pumpAndSettle();

    expect(preferences.aiOutputLanguage, AiOutputLanguage.persian);
    // The interface itself is untouched: someone reading Nex in English can
    // still want their Persian notes summarised in Persian.
    expect(preferences.locale, isNull);
  });

  testWidgets('picking an accent colour recolours the resolved theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(preferences.accentSeed, isNull);
    await tester.tap(find.text('Accent color'));
    await tester.pumpAndSettle();
    expect(find.byType(TagColorPicker), findsOneWidget);

    // The first swatch is the escape hatch — "Default" here, since an app
    // accent is never absent — and the second is the palette's first entry.
    final swatches = find.descendant(
      of: find.byType(TagColorPicker),
      matching: find.byType(InkWell),
    );
    await tester.tap(swatches.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(preferences.accentSeed, isNotNull);
    final seed = nexParseTagColor(preferences.accentSeed)!;
    final theme = Theme.of(tester.element(find.byType(TimelineScreen)));
    expect(theme.colorScheme.primary, nexAccentPaletteFrom(seed).light);
    // Not the shipped default — a colour someone did not pick would defeat
    // the whole point.
    expect(theme.colorScheme.primary, isNot(NexColors.defaultAccent.light));
  });

  testWidgets('each swipe edge picks from a list of its own', (tester) async {
    // The picker was a grid of preview cards, one grid per edge. That was
    // legible at two actions and a wall at seven, so each edge became a row
    // that opens its own list. The thing being asserted is unchanged: two
    // independent choices, and setting one leaves the other alone.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    // Where this row falls depends on how many sections sit above it, which
    // is not what this test is about.
    await tester.ensureVisible(find.text('Swipe actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Swipe actions'));
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuButton<SwipeAction>), findsNothing);
    expect(preferences.leadingAction, SwipeAction.addTag);

    // One row per edge, each naming what it currently does.
    await tester.tap(find.text('Swipe from the leading edge'));
    await tester.pumpAndSettle();

    // The whole set is offered, including the ones that arrived after the
    // gesture stopped being a pair.
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Remind'), findsOneWidget);

    await tester.tap(find.text('Nothing').last);
    await tester.pumpAndSettle();
    expect(preferences.leadingAction, SwipeAction.none);
    // The other edge is untouched — one edge's list does not leak into the
    // other's selection.
    expect(preferences.trailingAction, SwipeAction.delete);
  });

  testWidgets('the swipe arrows point the same way in Persian', (tester) async {
    // `Icons.arrow_forward` and `Icons.arrow_back` are declared
    // `matchTextDirection: true`, so `Icon` mirrors them itself under an RTL
    // `Directionality` — "forward" is already a leftward arrow in Persian.
    // This row used to swap them by hand as well, which flipped them twice:
    // both arrows pointed the way they do in English, so the leading row
    // described the trailing gesture and the trailing row the leading one, in
    // the app's primary language.
    //
    // What this pins is that the same icon is used in both directions. The
    // mirroring is the framework's job and asserting the rendered pixels
    // would be asserting Flutter's, not ours.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await preferences.setLocale('fa');
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('کشیدن انگشت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('کشیدن انگشت'));
    await tester.pumpAndSettle();

    // Sanity: the sheet really is right-to-left, or the rest proves nothing.
    expect(
      Directionality.of(tester.element(find.text('کشیدن از لبهٔ آغاز'))),
      TextDirection.rtl,
    );

    Finder arrowBeside(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
      matching: find.byType(Icon),
    );

    expect(
      (tester.widget<Icon>(arrowBeside('کشیدن از لبهٔ آغاز').first)).icon,
      Icons.arrow_forward,
      reason: 'the leading edge travels forward in either direction',
    );
    expect(
      (tester.widget<Icon>(arrowBeside('کشیدن از لبهٔ پایان').first)).icon,
      Icons.arrow_back,
    );
  });

  testWidgets('the full-screen photo viewer closes on a downward swipe', (
    tester,
  ) async {
    final path = p.join(services.mediaDir, 'p.jpg');
    final bytes = Uint8List.fromList(List.filled(200, 7));
    File(path).writeAsBytesSync(bytes);
    await services.capturePhoto(mediaUri: path, mediaHash: sha256OfBytes(bytes));
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NoteCard).first);
    await tester.pumpAndSettle();
    // Scoped to the detail sheet: the timeline card behind it has its own,
    // much smaller thumbnail.
    await tester.tap(
      find.descendant(
        of: find.byType(NoteDetailSheet),
        matching: find.byType(Image),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // A fixed point on the full-screen route rather than the viewer's own
    // center: the test image is not real JPEG bytes, so it never decodes,
    // and InteractiveViewer sizes to a child that never reports a size.
    // It used to take the AppBar's back arrow — nothing else closed it.
    await tester.dragFrom(const Offset(400, 300), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('dragging down over the settings content closes the sheet', (
    tester,
  ) async {
    // Reported symptom: swiping down closed Settings only when the drag
    // started on the empty header row above the scroll view — starting it
    // over the settings themselves, already scrolled to the top, did
    // nothing, since a plain SingleChildScrollView wins that vertical drag
    // outright whether or not it has anywhere left to scroll.
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Security'), findsOneWidget);

    await tester.drag(find.text('Security'), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(find.text('Security'), findsNothing);
  });

  testWidgets('the language picker shows every language in its own script', (
    tester,
  ) async {
    // Settings is a long list on a short test surface, and a scroll view
    // only mounts what is within reach.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    // Not a dropdown: all three are on screen at once, and each is labelled
    // the way a speaker of that language would recognise it.
    final picker = find.byType(NexChoiceCards<String>);
    expect(picker, findsOneWidget);
    expect(
      find.descendant(of: picker, matching: find.text('فارسی')),
      findsOneWidget,
    );

    await tester.tap(find.text('فارسی'));
    await tester.pumpAndSettle();

    expect(preferences.locale?.languageCode, 'fa');
  });

  testWidgets('a long note opens at reading height with its actions in reach', (
    tester,
  ) async {
    final long = List.filled(60, 'a sentence that keeps going.').join(' ');
    await services.captureText(long);
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NoteCard).first);
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byType(MaterialApp)).height;
    final sheet = tester.getSize(find.byType(NoteDetailSheet)).height;
    // It used to open as a strip at the bottom that had to be dragged up
    // before a word of a long note was readable.
    expect(sheet, greaterThan(screen * 0.6));

    // And the actions are pinned below the scroll, so a screenful of text does
    // not bury them: they are on screen without scrolling anywhere. The
    // action row is icon-only, so its members are found by tooltip rather
    // than by label text.
    expect(find.byTooltip('Delete').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Copy').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'Delete sits in the action row, unlabeled, and stays red among neutral icons',
    (tester) async {
      await services.captureText('a note');
      await services.refreshTimeline();
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('a note'));
      await tester.pumpAndSettle();

      final deleteTooltip = find.byTooltip('Delete');
      expect(deleteTooltip, findsOneWidget);
      // No printed "Delete" label anywhere in the sheet — tooltip only.
      expect(find.text('Delete'), findsNothing);

      final deleteIcon = tester.widget<Icon>(
        find.descendant(of: deleteTooltip, matching: find.byType(Icon)),
      );
      final copyIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byTooltip('Copy'),
          matching: find.byType(Icon),
        ),
      );
      final theme = Theme.of(tester.element(find.byType(NoteDetailSheet)));
      expect(deleteIcon.color, theme.colorScheme.error);
      expect(copyIcon.color, isNot(theme.colorScheme.error));
    },
  );

  testWidgets('the seams between action groups can actually be seen', (
    tester,
  ) async {
    // They were `outlineVariant` faded to 0.6 — the quiet token, quieter — on
    // the theory that a seam should be softer than a border. The result was
    // invisible in both themes, which makes it a seam that separates nothing.
    await services.captureText('a note');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('a note'));
    await tester.pumpAndSettle();

    final seams = find.byWidgetPredicate(
      (widget) => widget is Container && widget.constraints?.maxWidth == 1,
      description: 'a 1px separator',
    );
    expect(seams, findsWidgets, reason: 'the action row has no separators');

    final theme = Theme.of(tester.element(find.byType(NoteDetailSheet)));
    for (final element in seams.evaluate()) {
      final colour = ((element.widget as Container).color)!;
      // 3:1 is the floor for a boundary a person is meant to perceive
      // (WCAG 1.4.11). Measured against both surfaces the sheet can paint, so
      // this holds whichever one is behind the row, and composited first —
      // the separator is translucent, so its raw colour is not what anyone
      // sees.
      for (final ground in [
        theme.colorScheme.surface,
        theme.colorScheme.surfaceContainerLowest,
      ]) {
        expect(
          nexContrastRatio(Color.alphaBlend(colour, ground), ground),
          greaterThanOrEqualTo(3.0),
          reason: 'the separator is invisible against $ground',
        );
      }
    }
  });

  testWidgets('what the AI read is behind a tap, not on top of the note', (
    tester,
  ) async {
    final note = await services.captureVoice(
      mediaUri: p.join(tmp.path, 'media', 'said.m4a'),
      mediaHash: sha256OfBytes(Uint8List.fromList([1, 2, 3])),
      durationMs: 4000,
    );
    // As if the background pass had already transcribed it.
    testWorker.seedTranscript(note.id, 'the machine heard this');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NoteCard).first);
    await tester.pumpAndSettle();

    // Scoped to the sheet: the timeline card behind it previews a voice note
    // by its transcript, which is the card's job and not what this is about.
    Finder inSheet(Finder matching) =>
        find.descendant(of: find.byType(NoteDetailSheet), matching: matching);

    // The work happened on its own, but it does not open on top of the note.
    expect(inSheet(find.text('the machine heard this')), findsNothing);
    expect(inSheet(find.textContaining('Transcript')), findsOneWidget);

    await tester.ensureVisible(inSheet(find.textContaining('Transcript')));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(find.textContaining('Transcript')));
    await tester.pumpAndSettle();

    expect(inSheet(find.text('the machine heard this')), findsOneWidget);
  });

  testWidgets('a short note is still only as tall as it needs to be', (
    tester,
  ) async {
    await services.captureText('short');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NoteCard).first);
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byType(MaterialApp)).height;
    final sheet = tester.getSize(find.byType(NoteDetailSheet)).height;
    expect(sheet, lessThan(screen * 0.7));
  });

  testWidgets(
    "a voice note's long hidden transcript does not force reading height",
    (tester) async {
      // Tall enough that 70% of it clearly exceeds this content's natural
      // height — on the default 800x600 test surface the two are close
      // enough that the forced minimum never actually bound, and the bug
      // this guards against would have passed right along with the fix.
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Reported symptom: a rare, unexplained empty gap below Delete. The
      // sheet's "is this a long note" check counted the transcript even
      // while the AI panel that shows it was still collapsed — so whichever
      // recording happened to transcribe past 220 characters forced the
      // sheet to 70% of the screen for a view that was just a player and a
      // "Transcript ready" link, with nothing to fill the rest.
      //
      // Both notes here carry a transcript — a "Transcript ready" toggle of
      // its own either way — so only its *length* differs between them, not
      // whether the row exists at all. The two should still open at the same
      // height, since neither transcript is actually shown yet.
      final plain = await services.captureVoice(
        mediaUri: p.join(tmp.path, 'media', 'plain.m4a'),
        mediaHash: sha256OfBytes(Uint8List.fromList([1, 2, 3])),
        durationMs: 5000,
      );
      testWorker.seedTranscript(plain.id, 'short');
      final long = await services.captureVoice(
        mediaUri: p.join(tmp.path, 'media', 'long.m4a'),
        mediaHash: sha256OfBytes(Uint8List.fromList([1, 2, 3])),
        durationMs: 38000,
      );
      testWorker.seedTranscript(
        long.id,
        List.filled(40, 'a sentence that keeps going.').join(' '),
      );
      await services.refreshTimeline();
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NoteCard).first); // newest first: long
      await tester.pumpAndSettle();
      final longHeight = tester.getSize(find.byType(NoteDetailSheet)).height;
      Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NoteCard).last); // plain
      await tester.pumpAndSettle();
      final plainHeight = tester.getSize(find.byType(NoteDetailSheet)).height;

      expect(longHeight, closeTo(plainHeight, 1));
    },
  );

  testWidgets('a name turns the timeline header into a greeting', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    // No name and no AI provider means no header at all: the search field is
    // the first thing in the list.
    expect(find.textContaining('Sany'), findsNothing);

    await preferences.setDisplayName('  Sany  ');
    await tester.pumpAndSettle();

    // Trimmed, and only ever shown here — never sent anywhere, including to
    // the AI provider that writes the line beside it.
    expect(preferences.displayName, 'Sany');
    expect(find.textContaining('Sany'), findsOneWidget);

    await preferences.setDisplayName('');
    await tester.pumpAndSettle();
    expect(preferences.displayName, isNull);
    expect(find.textContaining('Sany'), findsNothing);
  });

  testWidgets('the greeting takes at most two words of a longer name', (
    tester,
  ) async {
    await preferences.setDisplayName('Sany   Karimi Nezhad');
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // Stored in full — the profile row has room for it. Only the greeting,
    // which shares a line with a mark, is cut.
    expect(preferences.displayName, 'Sany   Karimi Nezhad');
    expect(find.textContaining('Sany Karimi'), findsOneWidget);
    expect(find.textContaining('Nezhad'), findsNothing);
  });

  testWidgets('tapping the greeting re-rolls it when there is no AI', (
    tester,
  ) async {
    await preferences.setDisplayName('Sany');
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    String greeting() =>
        tester.widget<Text>(find.textContaining('Sany').first).data!;
    final before = greeting();

    await tester.tap(find.textContaining('Sany').first);
    await tester.pumpAndSettle();

    // The refresh never lands on the phrasing already showing — a button that
    // does nothing one time in three reads as broken.
    expect(greeting(), isNot(before));
  });

  testWidgets(
    'holding the capture button opens the assistant, tapping does not',
    (tester) async {
      // The assistant has no button of its own: capture and "ask about what I
      // captured" are the same intent at different lengths, and this screen has
      // one primary action rather than two.
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      // A plain tap is still a capture, unchanged.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureSheet), findsOneWidget);
      // The sheet's own submit button, which closes it — scoped to the sheet
      // because the FAB behind it carries the same tooltip.
      await tester.tap(
        find.descendant(
          of: find.byType(CaptureSheet),
          matching: find.byTooltip('Capture'),
        ),
      );
      await tester.pumpAndSettle();

      // Held, with no provider configured: the glow runs — it tracks the finger
      // and cannot know the outcome in advance — but nothing opens, because a
      // chat that can only answer "unavailable" is not worth the trip.
      expect(AiChatSheet.availableFor(preferences), isFalse);
      final press = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.add)),
      );
      // A frame to let the hold's ticker start before any time is advanced —
      // pumping 600ms straight away elapses it all before the first tick, and
      // the hold never progresses at all.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await press.up();
      await tester.pumpAndSettle();

      expect(find.byType(AiChatSheet), findsNothing);
      expect(find.byType(CaptureSheet), findsNothing);

      // With a provider behind it, the same hold opens the sheet.
      await preferences.setAiEnabled(true);
      await preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'sk-test'),
      );
      await tester.pumpAndSettle();
      expect(AiChatSheet.availableFor(preferences), isTrue);

      final hold = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.add)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await hold.up();
      await tester.pumpAndSettle();

      expect(find.byType(AiChatSheet), findsOneWidget);
      // Held, not tapped — the capture sheet must not have opened underneath.
      expect(find.byType(CaptureSheet), findsNothing);

      // The body scrolls the sheet itself in both of its states. A thread on
      // a controller of its own still scrolls, so nothing looks broken — the
      // sheet just stops growing when you drag it, which is the one gesture
      // the whole design rests on.
      ScrollController? bodyController() => tester
          .widget<ListView>(
            find.descendant(
              of: find.byType(AiChatSheet),
              matching: find.byType(ListView),
            ),
          )
          .controller;
      final beforeSending = bodyController();

      // No provider is reachable from a test, so this resolves to the failure
      // line — which is enough to swap the suggestions out for the thread.
      await tester.tap(find.byIcon(Icons.summarize_outlined));
      await tester.pumpAndSettle();

      expect(bodyController(), same(beforeSending));
    },
  );

  testWidgets('the greeting is centred, not aligned to one edge', (
    tester,
  ) async {
    await preferences.setDisplayName('Sany');
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // The header's own key is on a sliver, which has no box to measure — the
    // scroll view it lives in is the nearest thing that does, and the header
    // is laid out to its full width.
    final column = tester.getRect(find.byType(CustomScrollView));
    final words = tester.getRect(find.textContaining('Sany'));
    final mark = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('timeline-header')),
            matching: find.byWidgetPredicate(
              (w) => w is Text && w.data != null && !w.data!.contains('Sany'),
            ),
          )
          .first,
    );

    // The whole line — words and mark together — is what is centred, so the
    // words alone sit a little left of centre by exactly the mark's width.
    // Left-aligned, the greeting and the generated line under it read as two
    // separate starts stacked on each other rather than as one block.
    expect(words.expandToInclude(mark).center.dx, closeTo(column.center.dx, 2));
  });

  testWidgets('the greeting mark trails the words, in either direction', (
    tester,
  ) async {
    // It used to be baked into the front of the string, which put it at the
    // start — the right edge in Persian, the left in English. Separating it
    // out lets the Row place it at the trailing end in both.
    //
    // The Row takes its direction from the greeting's own text now, not from
    // the ambient locale: the strings the AI writes beside it follow the
    // language of the *notes*, which is not always the language of the
    // interface, and a Persian sentence laid out left-to-right puts its full
    // stop at the wrong end.
    // Driven by the *name*, not the interface language: the greeting is
    // written in whatever language the user wrote their own name in, so a
    // Persian name gets a Persian sentence — and a right-to-left one — even
    // while the app is in English.
    for (final (locale, name, script) in [
      ('fa', 'Sany', 'ltr'),
      ('en', 'سعید', 'rtl'),
    ]) {
      await preferences.setLocale(locale);
      await preferences.setDisplayName(name);
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      final words = tester.getRect(find.textContaining(name));
      // The mark is the one Text in the header that is not the greeting.
      final mark = tester.getRect(
        find
            .descendant(
              of: find.byKey(const ValueKey('timeline-header')),
              matching: find.byWidgetPredicate(
                (w) => w is Text && w.data != null && !w.data!.contains(name),
              ),
            )
            .first,
      );

      if (script == 'rtl') {
        expect(
          mark.center.dx,
          lessThan(words.center.dx),
          reason: 'trailing is the left edge in Persian',
        );
      } else {
        expect(mark.center.dx, greaterThan(words.center.dx));
      }
    }
  });

  test('the two swipe enums stay in step', () async {
    // The set is open (ADR-022) and it grew: Pin, Remind, Share and Ask were
    // all things the note detail sheet could already do, brought one gesture
    // closer. What has to hold is that the app's enum and the design system's
    // agree — every SwipeAction except `none` needs a panel to draw, and a
    // panel with no action behind it is a control that does nothing.
    expect(SwipeAction.values.map((e) => e.name).toList(), [
      'none',
      'delete',
      'addTag',
      'pin',
      'remind',
      'share',
      'ask',
    ]);
    expect(
      NexSwipeAction.values.map((e) => e.name).toSet(),
      SwipeAction.values.map((e) => e.name).toSet()..remove('none'),
    );
  });

  test('a stored swipe setting survives the round trip', () async {
    // The stored value is the wire name, not the index, so adding an action
    // in the middle of the enum cannot silently repoint someone's setting at
    // a different one.
    for (final action in SwipeAction.values) {
      expect(SwipeActionWire.fromWire(action.wireName), action);
    }
    // A name from a newer build. Falling back to delete is the documented
    // behaviour; what matters is that it is a real action rather than a crash.
    expect(SwipeActionWire.fromWire('teleport'), SwipeAction.delete);
  });

  test('each swipe edge is set on its own (ADR-022 revised)', () async {
    expect(preferences.leadingAction, SwipeAction.addTag);
    expect(preferences.trailingAction, SwipeAction.delete);

    // Setting one edge must leave the other exactly where it was. Coupling
    // them made the control a swap button wearing a menu's clothes.
    await preferences.setSwipeAction(
      isLeading: true,
      action: SwipeAction.delete,
    );
    expect(preferences.leadingAction, SwipeAction.delete);
    expect(preferences.trailingAction, SwipeAction.delete);

    // And an edge can carry nothing at all.
    await preferences.setSwipeAction(
      isLeading: false,
      action: SwipeAction.none,
    );
    expect(preferences.trailingAction, SwipeAction.none);
    expect(preferences.leadingAction, SwipeAction.delete);
  });
}
