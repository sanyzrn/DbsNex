import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/nex_services.dart';

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

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_client_');
    services = _testServices(tmp);
  });

  tearDown(() {
    services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('Timeline is home with capture FAB and no Save button',
      (tester) async {
    await tester.pumpWidget(NexApp(services: services));
    expect(find.text('Nex'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('Text capture chooser offers Text/Voice/Photo only', (tester) async {
    await tester.pumpWidget(NexApp(services: services));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  test('Text capture auto-saves via domain service', () {
    final note = services.capture.submitTextCapture('hello nex');
    expect(note, isNotNull);
    expect(services.search.timeline().first.content, 'hello nex');
  });

  test('Offline: capture/search/tag use local SQLite only', () {
    final note = services.capture.submitTextCapture('offline')!;
    services.tags.addTag(noteId: note.id, name: 'Work');
    final hits = services.search.search(const SearchFilters(query: 'offline'));
    expect(hits, hasLength(1));
    expect(hits.first.tags.first.name, 'Work');
  });

  test('Search budget: FTS query under 200ms for personal-scale data', () {
    for (var i = 0; i < 200; i++) {
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

  testWidgets('UI tokens apply bg-primary', (tester) async {
    await tester.pumpWidget(NexApp(services: services));
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      materialApp.theme!.scaffoldBackgroundColor,
      NexColors.bgPrimaryLight,
    );
    expect(
      materialApp.darkTheme!.scaffoldBackgroundColor,
      NexColors.bgPrimaryDark,
    );
  });
}
