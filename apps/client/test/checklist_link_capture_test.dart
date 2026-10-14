import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/link_reader.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/capture_sheet.dart';

import 'support/nex_harness.dart';

/// The two capture types added alongside text, voice, photo and file — from
/// the button in the capture sheet through to what the card shows.
/// The capture sheet's one field — the timeline has a search field too.
final _field = find.descendant(
  of: find.byType(CaptureSheet),
  matching: find.byType(TextField),
);

/// Its Send — the + button behind it is called Capture too.
final _send = find.descendant(
  of: find.byType(CaptureSheet),
  matching: find.byTooltip('Capture'),
);

void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_capture_',
      onboarded: false,
    );
    services = harness.services;
    preferences = harness.preferences;
    preferences = await NexPreferences.load();
    await preferences.completeOnboarding();
    await preferences.completeTour();
  });

  tearDown(() => harness.dispose());

  Future<void> openComposer(WidgetTester tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'one composer outline, adjacent text modes and direct media tools',
    (tester) async {
      await openComposer(tester);
      final sheet = find.byType(CaptureSheet);
      final text = tester.widget<TextField>(_field);
      final defaults = text.decoration!.applyDefaults(
        Theme.of(tester.element(_field)).inputDecorationTheme,
      );
      expect(defaults.filled, isFalse);
      expect(defaults.enabledBorder, InputBorder.none);
      expect(defaults.focusedBorder, InputBorder.none);
      Finder tool(String label) =>
          find.descendant(of: sheet, matching: find.byTooltip(label));
      final note = tool('Note');
      final checklist = tool('Checklist');
      final link = tool('Link');
      final voice = tool('Voice');
      expect(tester.getCenter(note).dy, tester.getCenter(checklist).dy);
      expect(tester.getCenter(note).dy, tester.getCenter(link).dy);
      expect(
        tester.getCenter(voice).dy,
        greaterThan(tester.getCenter(_field).dy),
      );
      for (final label in ['Camera', 'Gallery', 'File']) {
        expect(tool(label), findsOneWidget);
        expect(tester.getCenter(tool(label)).dy, tester.getCenter(voice).dy);
      }
      // The same field and draft survive all three text modes.
      final editor = tester.element(_field);
      await tester.enterText(_field, 'milk\neggs');
      for (final label in ['Checklist', 'Link', 'Note']) {
        await tester.tap(tool(label));
        await tester.pumpAndSettle();
        expect(tester.element(_field), same(editor));
        expect(tester.widget<TextField>(_field).controller!.text, 'milk\neggs');
      }
      await tester.tap(_send);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('capture tools fit a narrow phone in either language and theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final locale in ['en', 'fa']) {
      await preferences.setLocale(locale);
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        await preferences.setThemeMode(theme);
        await openComposer(tester);
        expect(tester.takeException(), isNull);
        final sheet = find.byType(CaptureSheet);
        expect(
          find.descendant(of: sheet, matching: find.byIcon(Icons.mic_none)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sheet,
            matching: find.byIcon(Icons.photo_library_outlined),
          ),
          findsOneWidget,
        );
        final send = find.descendant(
          of: sheet,
          matching: find.byKey(const ValueKey('capture-send')),
        );
        await tester.ensureVisible(send);
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('a checklist is captured as lines and shown as rows', (
    tester,
  ) async {
    await openComposer(tester);
    // The same sheet: the kind is switched at its top, in place.
    await tester.tap(find.byTooltip('Checklist'));
    await tester.pumpAndSettle();
    expect(find.text('An item, one per line'), findsOneWidget);

    // One field, one item per line — not five taps into five separate rows.
    await tester.enterText(_field, 'milk\nbread\nolives');
    await tester.pumpAndSettle();
    expect(find.text('3 items'), findsOneWidget);
    await tester.tap(_send);
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

  testWidgets('a note already written becomes a list in place, reminder '
      'and all, leaving nothing behind', (tester) async {
    await openComposer(tester);
    await tester.enterText(_field, 'milk\neggs');
    await tester.pumpAndSettle();
    // Saved as a note from the first keystroke (ADR-002)…
    final draft = (await services.timeline(limit: 5)).single;
    expect(draft.type, NoteType.text);
    final due = DateTime.now().add(const Duration(days: 1)).toUtc();
    await services.setDueAt(draft.id, due);

    // …and turned into a list without typing it again.
    await tester.tap(find.byTooltip('Checklist'));
    await tester.pumpAndSettle();
    expect(find.text('2 items'), findsOneWidget);
    // Back closes it the way Send does.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final notes = await services.timeline(limit: 5);
    expect(notes.single.type, NoteType.checklist);
    expect(notes.single.checklistItems.map((i) => i.text), ['milk', 'eggs']);
    expect(
      notes.single.dueAt?.millisecondsSinceEpoch,
      due.millisecondsSinceEpoch,
    );
    // The note it was is gone outright, not waiting in the trash.
    expect(await services.deletedNotes(), isEmpty);
    expect(await services.getById(draft.id), isNull);
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
    await openComposer(tester);
    await tester.tap(find.byTooltip('Link'));
    await tester.pumpAndSettle();

    // No scheme, the way people actually paste.
    await tester.enterText(_field, 'www.example.com/a');
    await tester.pumpAndSettle();
    // The site it will open, under the box, before anything is kept.
    expect(find.text('example.com'), findsOneWidget);
    await tester.tap(_send);
    await tester.pumpAndSettle();

    final notes = await services.timeline(limit: 5);
    expect(notes.single.type, NoteType.link);
    expect(notes.single.linkUrl, 'https://www.example.com/a');
    // The `www.` is dropped for display but kept in the stored URL — the
    // first is noise to a reader, the second has to still resolve.
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('a line written around a link becomes its caption', (
    tester,
  ) async {
    await openComposer(tester);
    await tester.tap(find.byTooltip('Link'));
    await tester.pumpAndSettle();
    await tester.enterText(_field, 'Friday dinner https://example.com/recipe');
    await tester.pumpAndSettle();
    expect(find.text('example.com · Friday dinner'), findsOneWidget);
    await tester.tap(_send);
    await tester.pumpAndSettle();

    final note = (await services.timeline(limit: 5)).single;
    expect(note.type, NoteType.link);
    expect(note.linkUrl, 'https://example.com/recipe');
    expect(note.caption, 'Friday dinner');
  });

  testWidgets('closing the sheet keeps a complete link (UX-03)', (
    tester,
  ) async {
    // "Close keeps" is what text and checklists teach; a link asked
    // "Discard?" instead.
    await openComposer(tester);
    await tester.tap(find.byTooltip('Link'));
    await tester.pumpAndSettle();

    await tester.enterText(_field, 'example.com/kept');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final notes = await services.timeline(limit: 5);
    expect(notes.single.linkUrl, 'https://example.com/kept');
  });

  testWidgets('closing on something that is not a link keeps it as a note', (
    tester,
  ) async {
    await openComposer(tester);
    await tester.tap(find.byTooltip('Link'));
    await tester.pumpAndSettle();

    await tester.enterText(_field, 'not a link');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Nothing written is thrown away, and the reason is said.
    final notes = await services.timeline(limit: 5);
    expect(notes.single.type, NoteType.text);
    expect(notes.single.content, 'not a link');
    expect(
      find.text('That is not a link, so it stays a note.'),
      findsOneWidget,
    );
  });

  testWidgets('a link that is not a link cannot be sent', (tester) async {
    await openComposer(tester);
    await tester.tap(find.byTooltip('Link'));
    await tester.pumpAndSettle();

    await tester.enterText(_field, 'javascript:alert(1)');
    await tester.pumpAndSettle();

    expect(find.text('That does not look like a link.'), findsOneWidget);
    // Send is there and does nothing: the sheet stays, and no link is made.
    await tester.tap(_send);
    await tester.pumpAndSettle();

    expect(find.text('That does not look like a link.'), findsOneWidget);
    final notes = await services.timeline(limit: 5);
    expect(notes.where((n) => n.type == NoteType.link), isEmpty);
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

    // The last open line finishes the list: it says so, with one haptic tap.
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('bread').last);
    await tester.pumpAndSettle();
    expect(find.text('All done · 2 of 2'), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.mediumImpact'));

    // No title action: naming a note by hand was offered for one version and
    // taken back out. Nex is not a filing app, and a capture is meant to be
    // finished the moment it exists.
    expect(find.byIcon(Icons.title), findsNothing);
  });

  testWidgets('the detail sheet edits the list, and the ticks survive', (
    tester,
  ) async {
    // A checklist could be ticked and nothing else: no way to fix a typo, add
    // the thing you forgot, or drop a line. The editor is the capture sheet
    // seeded with the list, so all three are the same gesture — and the one
    // thing it cannot carry by itself is what has been done, which is what
    // the second half of this checks.
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final note = (await services.captureChecklist(const [
      ChecklistItem(text: 'milk', done: true),
      ChecklistItem(text: 'bread', done: false),
    ]))!;
    await services.refreshTimeline();

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('milk').first);
    await tester.pumpAndSettle();

    final edit = find.byTooltip('Edit');
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();

    // Lines, not the storage format: no `- [x]` reaches the person editing.
    final field = find.byType(TextField).last;
    expect(tester.widget<TextField>(field).controller!.text, 'milk\nbread');

    await tester.enterText(field, 'milk\neggs');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = (await services.getById(note.id))!.checklistItems;
    expect(saved.map((i) => i.text), ['milk', 'eggs']);
    expect(
      saved.map((i) => i.done),
      [true, false],
      reason: 'milk was ticked before the edit and was not retyped',
    );
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
