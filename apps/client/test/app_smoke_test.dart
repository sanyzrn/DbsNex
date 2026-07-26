import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/os_capture_bridge.dart';

NexServices _testServices(Directory tmp) {
  final dbPath = p.join(tmp.path, 'nex.sqlite');
  final mediaDir = p.join(tmp.path, 'media');
  final backupDir = p.join(tmp.path, 'backups');
  Directory(mediaDir).createSync(recursive: true);
  Directory(backupDir).createSync(recursive: true);
  final db = NexDatabase.open(dbPath);
  final repo = NoteRepository(db);
  return NexServices.forTest(
    db: db,
    repo: repo,
    capture: CaptureService(repo, deviceId: 'test'),
    tags: TagService(repo),
    search: SearchService(repo),
    dbPath: dbPath,
    mediaDir: mediaDir,
    backupDir: backupDir,
  );
}

void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_client_');
    services = _testServices(tmp);
    preferences = await NexPreferences.load();
  });

  tearDown(() {
    services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('Timeline shows tag filter chip row with All', (tester) async {
    final note = services.capture.submitTextCapture('tagged')!;
    services.tags.addTag(noteId: note.id, name: 'Work', color: '#F0A93B');
    services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Work'), findsWidgets);
  });

  testWidgets('Capture sheet focuses text with Voice/Photo/File inline',
      (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    // Text is the default mode — a focused field, not a menu tile.
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    // Not a type-picker-first menu of four equal choices.
    expect(find.text('Text'), findsNothing);
    expect(find.text('Save'), findsNothing);
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
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
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
    expect(services.search.timeline().first.content, 'shared from another app');
  });

  test('OS share-intent photo auto-saves with media_hash', () async {
    final src = File(p.join(services.mediaDir, 'in.jpg'))
      ..writeAsBytesSync([1, 2, 3, 4, 5]);
    final bridge = OsCaptureBridge(services);
    await bridge.handle({'type': 'shared_photo', 'path': src.path});
    final note = services.search.timeline().first;
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
    final note = services.search.timeline().first;
    expect(note.type, NoteType.file);
    expect(note.content, 'Quarterly-Report.pdf');
    expect(note.mimeType, 'application/pdf');
    expect(note.content, isNot(contains('.bin')));
  });

  test('Optional caption on media notes is distinct from OCR/transcript', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final photo = services.capture.submitPhotoCapture(
      mediaUri: p.join(services.mediaDir, 'p.jpg'),
      mediaBytes: bytes,
    );
    expect(photo.caption, isNull);
    services.repo.setCaption(photo.id, 'whiteboard from sync');
    final updated = services.repo.getById(photo.id)!;
    expect(updated.caption, 'whiteboard from sync');
    expect(updated.ocrText, isNull);
  });

  test('Timeline tag filter returns only matching notes', () {
    final a = services.capture.submitTextCapture('alpha')!;
    final b = services.capture.submitTextCapture('beta')!;
    services.tags.addTag(noteId: a.id, name: 'Work');
    services.tags.addTag(noteId: b.id, name: 'Idea');
    final work = services.tags.listTags().firstWhere((t) => t.name == 'Work');
    final filtered = services.search.timeline(tagId: work.id);
    expect(filtered.map((n) => n.id), [a.id]);
  });

  test('Swipe mapping defaults and swap (ADR-022)', () async {
    expect(preferences.leadingAction, SwipeAction.addTag);
    expect(preferences.trailingAction, SwipeAction.delete);
    await preferences.swapSwipeMapping();
    expect(preferences.leadingAction, SwipeAction.delete);
    expect(preferences.trailingAction, SwipeAction.addTag);
  });

  test('Comfort Mode defaults off and toggles (ADR-023)', () async {
    expect(preferences.comfortMode, isFalse);
    await preferences.setComfortMode(true);
    expect(preferences.comfortMode, isTrue);
  });

  test('Theme mode defaults to System and can force Light/Dark', () async {
    expect(preferences.themeMode, ThemeMode.system);
    await preferences.setThemeMode(ThemeMode.dark);
    expect(preferences.themeMode, ThemeMode.dark);
    await preferences.setThemeMode(ThemeMode.light);
    expect(preferences.themeMode, ThemeMode.light);
  });

  test('File capture stores original filename for display', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
    final note = services.capture.submitFileCapture(
      mediaUri: p.join(services.mediaDir, 'doc.pdf'),
      mediaBytes: bytes,
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
    final listed = services.listBackups();
    expect(listed.map((f) => p.basename(f.path)), containsAll([
      'nex-2020.sqlite',
      'nex-2021.sqlite',
    ]));
    expect(listed.first.path, newer.path);
    expect(older.existsSync(), isTrue);
  });

  test('Comfort Mode tokens keep WCAG AA contrast', () {
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

  test('Soft-delete undo restores note', () {
    final note = services.capture.submitTextCapture('undo me')!;
    services.repo.softDelete(note.id);
    expect(services.search.timeline(), isEmpty);
    services.repo.undelete(note.id);
    expect(services.search.timeline().single.content, 'undo me');
  });

  test('Offline: capture/search/tag use local SQLite only', () {
    final note = services.capture.submitTextCapture('offline')!;
    services.tags.addTag(noteId: note.id, name: 'Work');
    final hits = services.search.search(const SearchFilters(query: 'offline'));
    expect(hits, hasLength(1));
    expect(hits.first.tags.first.name, 'Work');
  });

  test('Search budget: FTS under 200ms for 1000 notes (1.x.2 hardening)', () {
    for (var i = 0; i < 1000; i++) {
      services.capture.submitTextCapture('note number $i with keywords alpha');
    }
    final sw = Stopwatch()..start();
    final hits = services.search.search(const SearchFilters(query: 'alpha'));
    sw.stop();
    expect(hits.length, greaterThan(0));
    expect(sw.elapsedMilliseconds, lessThan(200));
  });

  test('Durable write budget: text capture under 300ms', () {
    final sw = Stopwatch()..start();
    services.capture.submitTextCapture('budget');
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(300));
  });

  test('Timeline page load under budget for large set', () {
    for (var i = 0; i < 2000; i++) {
      services.capture.submitTextCapture('bulk $i');
    }
    final sw = Stopwatch()..start();
    final page = services.search.timeline(limit: 50);
    sw.stop();
    expect(page, hasLength(50));
    expect(sw.elapsedMilliseconds, lessThan(200));
  });

  test('Voice capture stores hash; keyword search excludes it', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final voice = services.capture.submitVoiceCapture(
      mediaUri: p.join(services.mediaDir, 'v.m4a'),
      mediaBytes: bytes,
      durationMs: 900,
    );
    expect(voice.mediaHash, isNotNull);
    expect(
      services.search.search(const SearchFilters(query: 'anything')),
      isEmpty,
    );
  });

  test('AI preferences default on; cloud opt-in defaults off', () {
    expect(preferences.aiCapabilities.transcription, isTrue);
    expect(preferences.cloudAiOptIn, isFalse);
  });

  test('scheduleEnrichment does not block capture budget', () {
    final sw = Stopwatch()..start();
    final note = services.capture.submitTextCapture('enrich later')!;
    services.scheduleEnrichment(note.id);
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(300));
  });

  testWidgets('Settings sheet exposes Intelligence toggles', (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Intelligence'), findsOneWidget);
    expect(find.text('Transcription'), findsOneWidget);
    expect(find.text('Cloud AI (opt-in)'), findsOneWidget);
  });

  testWidgets('UI tokens apply bg-primary; Comfort swaps tokens',
      (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.scaffoldBackgroundColor, NexColors.bgPrimaryLight);

    await preferences.setComfortMode(true);
    await tester.pump();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.theme!.scaffoldBackgroundColor,
      NexColors.bgPrimaryLightComfort,
    );
  });

  testWidgets('Settings sheet exposes swipe + Appearance + Comfort',
      (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Swipe actions'), findsOneWidget);
    expect(find.text('Comfort Mode'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
  });

  test('No Pin/Archive swipe actions exist', () {
    expect(SwipeAction.values.map((e) => e.name).toList(), ['delete', 'addTag']);
    expect(NexSwipeAction.values.map((e) => e.name).toList(),
        ['delete', 'addTag']);
  });
}
