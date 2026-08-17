import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/link_reader.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/in_process_db.dart';

/// The two capture types added alongside text, voice, photo and file — from
/// the button in the capture sheet through to what the card shows.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_capture_');
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
    await preferences.completeOnboarding();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('a checklist is captured as lines and shown as rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Checklist'));
    await tester.pumpAndSettle();

    // One field, one item per line — not five taps into five separate rows.
    await tester.enterText(find.byType(TextField).last, 'milk\nbread\nolives');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();

    final notes = await services.timeline(limit: 5);
    expect(notes.single.type, NoteType.checklist);
    expect(notes.single.checklistItems.map((i) => i.text), [
      'milk',
      'bread',
      'olives',
    ]);

    // The card shows the first two, with the third counted rather than given
    // a row of its own.
    expect(find.text('milk'), findsOneWidget);
    expect(find.text('bread'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('ticking an item is an ordinary edit to the note', (
    tester,
  ) async {
    final note = (await services.captureChecklist(const [
      ChecklistItem(text: 'milk', done: false),
      ChecklistItem(text: 'bread', done: false),
    ]))!;

    await services.toggleChecklistItem(note.id, 0);

    final after = (await services.getById(note.id))!;
    expect(after.checklistItems.first.done, isTrue);
    // Same machinery as editing any other body: the revision moved and the
    // note is queued to sync again.
    expect(after.rev, greaterThan(note.rev));
    expect(after.syncState, SyncState.pending);
  });

  testWidgets('a link is normalised on the way in, and shows its host', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Link'));
    await tester.pumpAndSettle();

    // No scheme, the way people actually paste.
    await tester.enterText(find.byType(TextField).last, 'www.example.com/a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();

    final notes = await services.timeline(limit: 5);
    expect(notes.single.type, NoteType.link);
    expect(notes.single.linkUrl, 'https://www.example.com/a');
    // The `www.` is dropped for display but kept in the stored URL — the
    // first is noise to a reader, the second has to still resolve.
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('a link that is not a link cannot be captured', (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Link'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'javascript:alert(1)');
    await tester.pumpAndSettle();

    expect(find.text('That does not look like a link.'), findsOneWidget);

    // The button is disabled rather than hidden — see the sheet's own note —
    // so it is still there to tap, and tapping it does nothing. Asserted
    // through the behaviour rather than by reading `onPressed`: FilledButton
    // .icon builds a private subclass that a type finder does not match.
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();

    expect(await services.timeline(limit: 5), isEmpty);
    expect(find.text('That does not look like a link.'), findsOneWidget);
  });

  testWidgets('the detail sheet ticks an item, and offers no title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final note = (await services.captureChecklist(const [
      ChecklistItem(text: 'milk', done: false),
      ChecklistItem(text: 'bread', done: false),
    ]))!;
    await services.refreshTimeline();

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('milk').first);
    await tester.pumpAndSettle();

    // On the card the rows are a picture of the list; in the sheet they are
    // the list, and this is where ticking happens.
    expect(find.text('0 of 2'), findsOneWidget);
    await tester.tap(find.text('milk').last);
    await tester.pumpAndSettle();

    expect((await services.getById(note.id))!.checklistItems.first.done, true);
    expect(find.text('1 of 2'), findsOneWidget);

    // No title action: naming a note by hand was offered for one version and
    // taken back out. Nex is not a filing app, and a capture is meant to be
    // finished the moment it exists.
    expect(find.byIcon(Icons.title), findsNothing);
  });

  group('parseLinkPreview', () {
    test('prefers Open Graph, in either attribute order', () {
      const html = '''
<html><head>
<title>Fallback title</title>
<meta content="The real title" property="og:title">
<meta property="og:description" content="What the page is about">
</head></html>''';

      final preview = parseLinkPreview(html);
      expect(preview.title, 'The real title');
      expect(preview.excerpt, 'What the page is about');
    });

    test('falls back to <title> and the plain description', () {
      const html = '''
<html><head>
<title>  A  spaced   title  </title>
<meta name="description" content="Plain old description">
</head></html>''';

      final preview = parseLinkPreview(html);
      expect(preview.title, 'A spaced title');
      expect(preview.excerpt, 'Plain old description');
    });

    test('decodes the entities that actually turn up in titles', () {
      const html = '<html><head><title>Tom &amp; Jerry&#39;s</title></head>';
      expect(parseLinkPreview(html).title, "Tom & Jerry's");
    });

    test('a page with nothing useful is empty, not an error', () {
      expect(parseLinkPreview('<html><body>hi</body></html>').isEmpty, isTrue);
      expect(parseLinkPreview('').isEmpty, isTrue);
    });
  });
}
