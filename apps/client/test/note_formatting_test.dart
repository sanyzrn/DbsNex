import 'dart:io';

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
import 'package:nex_client/screens/note_detail_sheet.dart';

import 'support/in_process_db.dart';

/// A note's body is rendered where its writer formatted it and left exactly as
/// typed where they did not — the same predicate the card strips by, so the
/// two never disagree about what a note says.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_formatting_');
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

  Future<void> openText(WidgetTester tester, String body) async {
    final note = (await services.captureText(body))!;
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a formatted note is rendered, markers and all gone', (
    tester,
  ) async {
    await openText(tester, 'the **urgent** one');

    expect(find.byType(NexMarkdown), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('an ordinary sentence is shown exactly as typed', (tester) async {
    // The cost of getting this wrong is a character the writer put there being
    // eaten: `2 * 3 * 4` through a Markdown parser loses two operators.
    await openText(tester, '2 * 3 * 4');

    expect(find.byType(NexMarkdown), findsNothing);
    expect(find.byType(NexBodyText), findsWidgets);
    expect(find.textContaining('2 * 3 * 4'), findsOneWidget);
  });

  testWidgets('a Persian list is rendered as a list', (tester) async {
    await openText(tester, '- مورد اول\n- مورد دوم');

    expect(find.byType(NexMarkdown), findsOneWidget);
    expect(find.textContaining('مورد اول'), findsWidgets);
  });

  group('a tapped code span is copied', () {
    /// Everything the platform channel was asked to put on the clipboard.
    List<String> watchClipboard(WidgetTester tester) {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map)['text'] as String,
            );
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
      return copied;
    }

    testWidgets('one touch takes the mono part', (tester) async {
      // A note that is only the span, so the tap can be aimed by finding its
      // text. Inside a sentence the renderer merges every inline run into one
      // rich text, and hitting the span would mean computing an offset into a
      // paragraph — which tests the arithmetic, not the wiring.
      final copied = watchClipboard(tester);
      await openText(tester, '`flutter test`');

      await tester.tap(find.text('flutter test', findRichText: true));
      await tester.pumpAndSettle();

      expect(copied, ['flutter test']);
    });

    testWidgets('a fenced block is left as a block', (tester) async {
      // It already scrolls sideways, and turning the whole of it into one tap
      // target would take that away.
      final copied = watchClipboard(tester);
      await openText(tester, '```\nfinal x = 1;\n```');

      await tester.tap(
        find.textContaining('final x = 1;', findRichText: true).first,
      );
      await tester.pumpAndSettle();

      expect(copied, isEmpty);
    });
  });
}
