import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_client/documents/docx_markdown.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';

import 'support/in_process_db.dart';

/// A file note used to be a filename and a byte count, with one exception:
/// Markdown, which was read off disk and rendered. Everything else that could
/// have been shown the same way was invisible for want of a predicate.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_file_preview_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    Directory(p.join(tmp.path, 'media')).createSync(recursive: true);
    Directory(p.join(tmp.path, 'backups')).createSync(recursive: true);
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: p.join(tmp.path, 'media'),
      backupDir: p.join(tmp.path, 'backups'),
    );
    preferences = await NexPreferences.load();
  });

  final realDocxReader = nexDocxReader;

  tearDown(() async {
    nexDocxReader = realDocxReader;
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> openNote(WidgetTester tester, Note note) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          // A loading skeleton shimmers on a repeating controller, which
          // requests a frame forever — `pumpAndSettle` never returns while one
          // is on screen. Reduce-motion stops it, which is what this is.
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: NoteDetailSheet(
              services: services,
              noteId: note.id,
              preferences: preferences,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Writes [name] into the media directory and opens it as a file note.
  Future<void> openFile(
    WidgetTester tester,
    String name, {
    String? text,
    List<int>? bytes,
    String? mimeType,
  }) async {
    final file = File(p.join(tmp.path, name));
    if (bytes != null) {
      file.writeAsBytesSync(bytes);
    } else {
      file.writeAsStringSync(text ?? '');
    }
    await openNote(
      tester,
      await services.captureFile(
        mediaUri: file.path,
        mediaBytes: file.readAsBytesSync(),
        originalFilename: name,
        mimeType: mimeType,
      ),
    );
  }

  group('text the app can render', () {
    testWidgets('Markdown arrives rendered, not as its own source', (
      tester,
    ) async {
      await openFile(
        tester,
        'plan.md',
        text: '# سرتیتر\n\n- مورد اول\n- مورد دوم\n',
        mimeType: 'text/markdown',
      );

      // The filename is still there — this adds to the row, it does not
      // replace it.
      expect(find.text('plan.md'), findsOneWidget);
      expect(find.byType(NexMarkdown), findsOneWidget);
      expect(find.textContaining('سرتیتر'), findsWidgets);
      expect(find.textContaining('# سرتیتر'), findsNothing);
    });

    testWidgets('a .txt is shown as written, not read as Markdown', (
      tester,
    ) async {
      // The distinction the old predicate could not make. A shopping list
      // whose first line begins with `#` has no heading in it.
      await openFile(tester, 'list.txt', text: '# milk\n# bread\n');

      expect(find.byType(NexMarkdown), findsNothing);
      expect(find.textContaining('# milk'), findsOneWidget);
    });

    testWidgets('source is shown in a monospace block', (tester) async {
      await openFile(tester, 'main.dart', text: 'void main() {\n  run();\n}\n');

      expect(find.byType(NexMarkdown), findsNothing);
      expect(find.byType(SelectableText), findsOneWidget);
      final code = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(code.data, contains('void main()'));
      expect(code.style?.fontFamily, 'monospace');
      // Source is left to right whatever the interface is doing, or the
      // indentation of every line ends up on the wrong side.
      expect(code.textDirection, TextDirection.ltr);
    });

    testWidgets('a CSV is drawn as a table', (tester) async {
      await openFile(
        tester,
        'costs.csv',
        text: 'city,total\n"Tehran, Iran",2\nShiraz,3\n',
      );

      expect(find.byType(Table), findsOneWidget);
      expect(find.text('city'), findsOneWidget);
      // The quoted field is one cell, not two — the reason the parser is a
      // scanner rather than a `split`.
      expect(find.text('Tehran, Iran'), findsOneWidget);
      expect(find.text('Shiraz'), findsOneWidget);
    });

    testWidgets('a long table is drawn short and says so', (tester) async {
      final rows = [
        for (var i = 0; i < 260; i++) 'row$i,$i',
      ].join('\n');
      await openFile(tester, 'big.csv', text: 'name,n\n$rows\n');

      expect(find.byType(Table), findsOneWidget);
      // Not a table that simply stops: one that stops and explains itself.
      expect(find.textContaining('Showing the first 200'), findsOneWidget);
      expect(find.text('row0'), findsOneWidget);
      expect(find.text('row259'), findsNothing);
    });

    testWidgets('a file too large to render says so', (tester) async {
      await openFile(tester, 'huge.md', text: 'x' * (512 * 1024 + 1));

      // Not silence. A preview that shows nothing is indistinguishable from a
      // file that has nothing in it.
      expect(find.textContaining('Too large'), findsOneWidget);
      expect(find.byType(NexMarkdown), findsNothing);
    });
  });

  group('files that are not text', () {
    // A 1×1 PNG, so the decode is a real one rather than a call on the
    // error path.
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
      'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );

    testWidgets('an image shared as a file is shown, not just named', (
      tester,
    ) async {
      // The same picture looked entirely different depending on which door it
      // came in by: captured, it was shown; shared, it was a byte count.
      await openFile(tester, 'photo.png', bytes: pngBytes);

      expect(find.text('photo.png'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('audio is not decoded as text', (tester) async {
      // The player itself needs a platform plugin no widget test registers,
      // so what is asserted here is the routing: an .mp3 must never reach the
      // text reader and render its own bytes as mojibake.
      await openFile(tester, 'song.mp3', bytes: [0xFF, 0xFB, 0x90, 0x00]);

      expect(find.text('song.mp3'), findsOneWidget);
      expect(find.byType(NexMarkdown), findsNothing);
      expect(find.byType(Table), findsNothing);
    });

    /// A `.docx` holding one styled paragraph.
    List<int> docxBytes(String text, String style) {
      final archive = Archive();
      final xml = utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><w:body>'
        '<w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr>'
        '<w:r><w:t>$text</w:t></w:r></w:p>'
        '</w:body></w:document>',
      );
      archive.addFile(ArchiveFile('word/document.xml', xml.length, xml));
      return ZipEncoder().encodeBytes(archive);
    }

    testWidgets('a .docx is read off disk and shown as a document', (
      tester,
    ) async {
      // In the app the parse happens on another isolate, and a widget test's
      // fake-async zone never hears back from one — so the reader is swapped
      // for a same-isolate one. What is under test is the wiring either way:
      // that a `.docx` reaches the document reader and its Markdown reaches
      // the screen.
      nexDocxReader = (bytes) async => NexDocx.read(bytes);
      await openFile(
        tester,
        'plan.docx',
        bytes: docxBytes('Chapter one', 'Heading1'),
      );
      await tester.pumpAndSettle();

      expect(find.text('plan.docx'), findsOneWidget);
      expect(find.byType(NexMarkdown), findsOneWidget);
      // Rendered as the heading it was styled as, without its hash.
      expect(find.textContaining('Chapter one'), findsWidgets);
      expect(find.textContaining('# Chapter one'), findsNothing);
    });

    testWidgets('a PDF shows its first page, drawn by the platform', (
      tester,
    ) async {
      // The rendering is Android's own, over the channel the share intent
      // uses; here it is mocked, because a widget test runs on the host.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('nex/os_capture'),
            (call) async =>
                call.method == 'pdfPreview' ? pngBytes : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('nex/os_capture'),
              null,
            ),
      );
      await openFile(
        tester,
        'report.pdf',
        text: '%PDF-1.4 not really',
        mimeType: 'application/pdf',
      );
      await tester.pumpAndSettle();

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      // A picture of the page, not a reader: nothing is parsed out of it.
      expect(find.byType(NexMarkdown), findsNothing);
    });

    testWidgets('a video shows a frame of itself, drawn by the platform', (
      tester,
    ) async {
      // A cover, not a player. Playing video in a note means a codec plugin
      // and a render surface; the question a note raises about a video is
      // which one it is, and one frame answers it.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('nex/os_capture'),
            (call) async => call.method == 'videoPreview' ? pngBytes : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('nex/os_capture'),
              null,
            ),
      );
      await openFile(
        tester,
        'clip.mp4',
        bytes: [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70],
        mimeType: 'video/mp4',
      );
      await tester.pumpAndSettle();

      expect(find.text('clip.mp4'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      // What tells the still from the video, and the reason the frame is
      // worth showing at all rather than being mistaken for a photo.
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      // Nothing is parsed out of it, and the bytes never reach the text
      // reader.
      expect(find.byType(NexMarkdown), findsNothing);
    });

    testWidgets('a video with no retriever is named and left alone', (
      tester,
    ) async {
      // No mock handler, so the channel throws MissingPluginException — an
      // absence, not an error, exactly as with the PDF.
      await openFile(
        tester,
        'clip.mp4',
        bytes: [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70],
        mimeType: 'video/mp4',
      );

      expect(find.text('clip.mp4'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byType(NexMarkdown), findsNothing);
    });

    testWidgets('a PDF with no renderer is named and left alone', (
      tester,
    ) async {
      // No mock handler, so the channel throws MissingPluginException — which
      // is what Windows does, and what an Android build without the native
      // half would do. It is an absence, not an error.
      await openFile(
        tester,
        'report.pdf',
        text: '%PDF-1.4 not really',
        mimeType: 'application/pdf',
      );

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(NexMarkdown), findsNothing);
      expect(find.byType(Table), findsNothing);
    });
  });
}
