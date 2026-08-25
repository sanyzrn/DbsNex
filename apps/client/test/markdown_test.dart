import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';

import 'support/in_process_db.dart';

/// Markdown reaches the app in two shapes: a `.md` file shared into it, and
/// every answer the assistant writes. Neither was rendered — the file was a
/// filename and a size, and the answer was its own asterisks.
void main() {
  group('nexIsMarkdownFile', () {
    test('recognises the extensions and the MIME type', () {
      expect(nexIsMarkdownFile(path: '/x/notes.md'), isTrue);
      expect(nexIsMarkdownFile(path: '/x/NOTES.MD'), isTrue);
      expect(nexIsMarkdownFile(path: '/x/notes.markdown'), isTrue);
      // Android's share sheet is generous with octet-stream, so the name is
      // often the only thing that knows — and sometimes the reverse.
      expect(
        nexIsMarkdownFile(path: '/x/notes', mimeType: 'text/markdown'),
        isTrue,
      );
      expect(
        nexIsMarkdownFile(
          path: '/x/notes.md',
          mimeType: 'application/octet-stream',
        ),
        isTrue,
      );
      expect(
        nexIsMarkdownFile(
          path: '/x/a.md',
          mimeType: 'text/markdown; charset=utf-8',
        ),
        isTrue,
      );
    });

    test('leaves every other file alone', () {
      expect(nexIsMarkdownFile(path: null), isFalse);
      expect(nexIsMarkdownFile(path: ''), isFalse);
      expect(nexIsMarkdownFile(path: '/x/photo.png'), isFalse);
      expect(nexIsMarkdownFile(path: '/x/report.pdf'), isFalse);
      expect(nexIsMarkdownFile(path: '/x/notes.txt'), isFalse);
    });
  });

  group('a Markdown note is read, not just named', () {
    late Directory tmp;
    late NexServices services;
    late NexPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('nex_markdown_');
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

    tearDown(() async {
      await services.dispose();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<void> openNote(WidgetTester tester, Note note) async {
      final app = MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteDetailSheet(
            services: services,
            noteId: note.id,
            preferences: preferences,
          ),
        ),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
    }

    Future<void> openFileNote(WidgetTester tester, File file) async {
      final note = await services.captureFile(
        mediaUri: file.path,
        mediaBytes: file.readAsBytesSync(),
        originalFilename: p.basename(file.path),
        mimeType: 'text/markdown',
      );
      await openNote(tester, note);
    }

    testWidgets('the file\'s own words are on screen, rendered', (
      tester,
    ) async {
      final file = File(p.join(tmp.path, 'plan.md'))
        ..writeAsStringSync('# سرتیتر\n\n- مورد اول\n- مورد دوم\n');
      await openFileNote(tester, file);

      // The filename is still there — this adds to the row, it does not
      // replace it.
      expect(find.text('plan.md'), findsOneWidget);
      // And the contents are rendered rather than shown as their source: the
      // heading arrives without its hash.
      expect(find.byType(NexMarkdown), findsOneWidget);
      expect(find.textContaining('سرتیتر'), findsWidgets);
      expect(find.textContaining('# سرتیتر'), findsNothing);
    });

    testWidgets('a file too large to render says so', (tester) async {
      final file = File(p.join(tmp.path, 'huge.md'))
        ..writeAsStringSync('x' * (512 * 1024 + 1));
      await openFileNote(tester, file);

      // Not silence. A preview that shows nothing is indistinguishable from a
      // file that has nothing in it.
      expect(find.textContaining('Too large'), findsOneWidget);
      expect(find.byType(NexMarkdown), findsNothing);
    });

    testWidgets('a file that is not Markdown is left alone', (tester) async {
      final file = File(p.join(tmp.path, 'report.pdf'))
        ..writeAsStringSync('%PDF-1.4 not really');
      await openNote(
        tester,
        await services.captureFile(
          mediaUri: file.path,
          mediaBytes: file.readAsBytesSync(),
          originalFilename: 'report.pdf',
          mimeType: 'application/pdf',
        ),
      );

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.byType(NexMarkdown), findsNothing);
    });
  });
}
