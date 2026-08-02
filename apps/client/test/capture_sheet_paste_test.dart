import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_process_db.dart';

/// The capture sheet's clipboard affordance: a chip appears when the OS
/// clipboard holds text, and one tap turns it into a note the same way a
/// keystroke would (ADR-002 — no Save button, the note exists the moment the
/// content does).
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_paste_');
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void mockClipboard(String? text) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': text};
      }
      return null;
    });
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CaptureSheet(
            services: services,
            preferences: preferences,
            onVoice: () {},
            onCamera: () {},
            onGallery: () {},
            onFile: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('text on the clipboard offers a paste chip', (tester) async {
    mockClipboard('hello from the clipboard');
    await pumpSheet(tester);

    expect(find.byIcon(Icons.content_paste), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
  });

  testWidgets('an empty clipboard offers nothing', (tester) async {
    mockClipboard('');
    await pumpSheet(tester);

    expect(find.byIcon(Icons.content_paste), findsNothing);
  });

  testWidgets('no clipboard at all offers nothing', (tester) async {
    mockClipboard(null);
    await pumpSheet(tester);

    expect(find.byIcon(Icons.content_paste), findsNothing);
  });

  testWidgets('pasting creates the note exactly as a keystroke would', (
    tester,
  ) async {
    mockClipboard('captured by paste');
    await pumpSheet(tester);

    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'captured by paste');

    // The chip is gone — the clipboard is consumed.
    expect(find.byIcon(Icons.content_paste), findsNothing);

    // ADR-002: the note exists the moment the content does.
    await tester.pumpAndSettle();
    final notes = await services.timeline();
    expect(notes.single.content, 'captured by paste');
  });

  testWidgets('pasting appends at the cursor when the field already has text', (
    tester,
  ) async {
    mockClipboard('!');
    await pumpSheet(tester);

    // Type something first, then paste at the end.
    await tester.enterText(find.byType(TextField), 'draft');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'draft!');
  });
}
