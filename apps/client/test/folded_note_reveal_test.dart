import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';

import 'support/nex_harness.dart';

/// Opening a long piece of reading used to cost the reader two waits: the
/// whole document was deferred behind the sheet's rise even though only a
/// folded first page was ever going to be drawn, and the tap on More built
/// the whole document in the tap's own frame. The first wait is gone and the
/// second is paced — this file pins both, and the pieces of the pacing that
/// could change what a document *renders* rather than how fast.
void main() {
  late NexTestHarness harness;
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_folded_reveal_',
      onboarded: false,
    );
    services = harness.services;
    preferences = harness.preferences;
    tmp = harness.root;
  });

  tearDown(() => harness.dispose());

  /// Pumps the detail sheet for [note] — the tree every test below reads
  /// in.
  Future<void> openSheet(WidgetTester tester, Note note) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          // A skeleton shimmers on a repeating controller, which requests a
          // frame forever — `pumpAndSettle` never returns while one is on
          // screen. Reduce-motion stops it, which is what this is.
          data: const MediaQueryData(
            size: Size(800, 600),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: NoteDetailSheet(
              services: services,
              noteId: note.id,
              preferences: preferences,
              initialNote: note,
            ),
          ),
        ),
      ),
    );
  }

  /// Opens [name], written into the media directory, as a file note.
  Future<Note> openFile(
    WidgetTester tester,
    String name,
    String text, {
    String? mimeType,
  }) async {
    final file = File(p.join(tmp.path, name));
    file.writeAsStringSync(text);
    final note = await services.captureFile(
      mediaUri: file.path,
      mediaHash: sha256OfBytes(file.readAsBytesSync()),
      originalFilename: name,
      mimeType: mimeType,
    );
    await openSheet(tester, note);
    return note;
  }

  /// A Markdown document past every threshold in the reader: well over the
  /// fold, over the size where opening in one piece stopped being honest,
  /// with blank-line paragraphs so slicing has boundaries to use.
  String markdownDoc({int paragraphs = 40}) => [
    for (var i = 0; i < paragraphs; i++)
      i == 0
          ? 'FIRST paragraph of the document, plain prose.'
          : 'Paragraph $i of the long document, plain prose.',
  ].join('\n\n');

  testWidgets('a long Markdown file opens with its preview in the sheet', (
    tester,
  ) async {
    // Past the eight kilobytes where the whole body used to wait for the
    // sheet to finish rising. The first page folds, so it is drawn in the
    // sheet's own first frame instead.
    await openFile(
      tester,
      'long-open.md',
      markdownDoc(paragraphs: 200),
      mimeType: 'text/markdown',
    );

    expect(find.textContaining('FIRST paragraph'), findsOneWidget);
    // The fold held: the end of the document is not on the first page.
    expect(find.textContaining('Paragraph 199'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.textContaining('FIRST paragraph'), findsOneWidget);
  });

  testWidgets('expanding opens the first slice in the tap frame and finishes', (
    tester,
  ) async {
    await openFile(
      tester,
      'long-more.md',
      markdownDoc(paragraphs: 200),
      mimeType: 'text/markdown',
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);

    // One frame after the tap: the page is open — the first slice is built
    // in the tap's own frame, so the tap has something to show for itself.
    await tester.pump();
    expect(find.textContaining('FIRST paragraph'), findsOneWidget);
    expect(find.textContaining('Paragraph 199'), findsNothing);
    // The rest arrives over the frames that follow, not this one.
    expect(
      find.byType(NexMarkdown),
      findsOneWidget,
      reason: 'one slice in the tap frame',
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('Paragraph 199'), findsOneWidget);
    expect(
      find.byType(NexMarkdown),
      greaterThan(1),
      reason: 'the document opened in slices',
    );

    // Folding back, then opening again: the second opening is paced too, and
    // the page still completes.
    await Scrollable.ensureVisible(
      tester.element(find.text('Less').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Less').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paragraph 199'), findsNothing);
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paragraph 199'), findsOneWidget);
  });

  testWidgets('a document small enough opens as one body, as before', (
    tester,
  ) async {
    // Over the fold, under the size where slicing begins: expanding renders
    // exactly the one Markdown body it always did.
    await openFile(
      tester,
      'small.md',
      markdownDoc(paragraphs: 30),
      mimeType: 'text/markdown',
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();

    expect(find.byType(NexMarkdown), findsOneWidget);
    expect(find.textContaining('Paragraph 29'), findsOneWidget);
  });

  testWidgets('a document carrying reference definitions opens whole', (
    tester,
  ) async {
    // A definition anywhere keeps the document in one piece rather than
    // slice it in a way the link at the top could not survive.
    final source =
        'Read [the site][nex] early in the document.\n\n'
        '${markdownDoc(paragraphs: 200)}\n\n'
        '[nex]: https://example.com/defined';
    await openFile(tester, 'defined.md', source, mimeType: 'text/markdown');
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();

    // One body, past the size where slicing would otherwise begin: the
    // definition is what kept it whole.
    expect(find.byType(NexMarkdown), findsOneWidget);
    // The link is a link, not the brackets that wrote it.
    expect(find.textContaining('the site'), findsOneWidget);
    expect(find.textContaining('[the site][nex]'), findsNothing);
  });

  testWidgets('an English paragraph keeps a Persian document its direction', (
    tester,
  ) async {
    // Sized so the paragraph after the first sixty Persian ones — the
    // English one — starts the second slice: a slice whose own first strong
    // character is English, so only the document's direction keeps it on
    // the page's side.
    String persian(int from, int to) => [
      for (var i = from; i < to; i++)
        'پاراگراف فارسی شماره‌ی $i درباره‌ی موضوعاتی که متن را بلند می‌کنند.',
    ].join('\n\n');
    final source = [
      persian(0, 60),
      'A LATE paragraph that is entirely in English.',
      persian(60, 100),
    ].join('\n\n');
    await openFile(tester, 'mixed.md', source, mimeType: 'text/markdown');
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();

    final english = find.textContaining('A LATE paragraph');
    expect(english, findsOneWidget);
    // The document is Persian: its direction is the one every slice renders
    // in, including the one holding only English words.
    final page = tester
        .element(english)
        .findAncestorWidgetOfExactType<Directionality>();
    expect(page?.textDirection, TextDirection.rtl);
  });

  testWidgets('source code stays one block, whatever its size', (tester) async {
    final padding = '  // line of source padding the file out.\n';
    await openFile(tester, 'big.dart', 'void main() {\n${padding * 300}}\n');
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();

    // One monospace block that scrolls sideways — not several, which would
    // give the file a border and a scrollbar per slice.
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('a big table still waits for the sheet to open', (tester) async {
    final rows = [
      for (var i = 0; i < 260; i++)
        'row-$i,padded-out-so-the-file-passes-eight-kilobytes,$i',
    ].join('\n');
    await openFile(tester, 'big-table.csv', 'name,note,n\n$rows\n');

    // Right after mounting: the sheet is rising at its final height with
    // the table's place held, not the table itself.
    expect(find.byType(Table), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('Showing the first 200'), findsOneWidget);
    expect(find.text('row-0'), findsOneWidget);
    expect(find.text('row-259'), findsNothing);
  });

  testWidgets('a note of nothing but blank lines opens without crashing', (
    tester,
  ) async {
    // Capture keeps intentional whitespace — only a truly empty note is
    // discarded — so a page of blank lines is a note the app really holds.
    // Slicing it once produced no slices at all, and the first reveal then
    // read past the end of nothing.
    final note = (await services.captureText('   \n\n  \n' * 2500))!;
    await openSheet(tester, note);
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();

    // The page opened — to nothing, which is what the note says — and the
    // way back works too.
    expect(find.text('Less'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('Less').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Less').first);
    await tester.pumpAndSettle();
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('a loose list opens as the one list it is', (tester) async {
    // Blank lines between items make one loose list. Past the size where
    // slicing begins, and under the ceiling where even a list is cut, the
    // blank line between two items is the middle of the list, not a
    // boundary between blocks — the page opens holding one list, not a
    // stack of lists that happen to sit adjacent.
    final items = [
      for (var i = 0; i < 150; i++)
        '- item $i of a loose list, padded so the document grows past slicing',
    ].join('\n\n');
    await openFile(tester, 'loose.md', items, mimeType: 'text/markdown');
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();

    expect(find.byType(NexMarkdown), findsOneWidget);
    expect(find.textContaining('item 149'), findsOneWidget);
  });

  testWidgets('an indented code block keeps its blank lines to itself', (
    tester,
  ) async {
    // An indented block's own blank lines, each followed by more indented
    // lines, are inside the block: a boundary at one would end it early and
    // begin a second block beside it. A heading up top is what makes the
    // file read as Markdown at all.
    final parts = <String>['# Indented code below', ''];
    for (var i = 0; i < 140; i++) {
      parts.add('    indented line $i of a code block, padded out to size');
      if (i % 10 == 9) parts.add('');
    }
    await openFile(
      tester,
      'indented.md',
      parts.join('\n'),
      mimeType: 'text/markdown',
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();

    // One body: the block was never cut at one of its own blank lines.
    expect(find.byType(NexMarkdown), findsOneWidget);
  });
  testWidgets('slicing preserves every source character including whitespace', (
    tester,
  ) async {
    final source = '  \n\n${markdownDoc(paragraphs: 200)}\n  \n';
    await openFile(
      tester,
      'preserve-space.md',
      source,
      mimeType: 'text/markdown',
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();

    final slices = tester.widgetList<NexMarkdown>(find.byType(NexMarkdown));
    expect(slices.length, greaterThan(1));
    expect(slices.map((part) => part.text).join(), source);
  });

  testWidgets('a four-tick fence is not closed by three ticks', (tester) async {
    final longLine = List.filled(5000, 'x').join();
    final fenced = [
      '````dart',
      longLine,
      '```',
      '',
      'final stillInside = true;',
      '````',
    ].join('\n');
    final source =
        '${markdownDoc(paragraphs: 120)}\n\n$fenced\n\n'
        '${markdownDoc(paragraphs: 120)}';
    await openFile(
      tester,
      'four-tick-fence.md',
      source,
      mimeType: 'text/markdown',
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('More').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();

    final slices = tester
        .widgetList<NexMarkdown>(find.byType(NexMarkdown))
        .map((part) => part.text)
        .toList();
    final fenceSlices = slices.where((part) => part.contains('````dart'));
    expect(fenceSlices, hasLength(1));
    expect(fenceSlices.single, contains('final stillInside = true;'));
    expect(fenceSlices.single, contains('\n````'));
  });
}
