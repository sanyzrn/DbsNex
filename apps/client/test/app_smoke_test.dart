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

  testWidgets('Timeline is home with capture FAB and no Save button',
      (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    expect(find.text('Nex'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('Text capture chooser offers Text/Voice/Photo only',
      (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
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

  testWidgets('Settings sheet exposes swipe + Comfort preference groups',
      (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Swipe actions'), findsOneWidget);
    expect(find.text('Comfort Mode'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
  });

  test('No Pin/Archive swipe actions exist', () {
    expect(SwipeAction.values.map((e) => e.name).toList(), ['delete', 'addTag']);
    expect(NexSwipeAction.values.map((e) => e.name).toList(),
        ['delete', 'addTag']);
  });
}
