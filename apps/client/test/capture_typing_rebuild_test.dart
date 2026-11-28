import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/capture_sheet.dart';

import 'support/in_process_db.dart';
import 'support/text_input.dart';

/// NEX-UI-02: the capture sheet rebuilt its whole chrome — the kind bar, the
/// composer box's AnimatedContainer → AnimatedSize → AnimatedSwitcher chain,
/// the tools wrap — once per keystroke, when the only thing its build reads
/// of the text is whether there is any. The rebuilds now happen on the
/// empty↔typed flips; the editor's own sheet did the same fix in 2.6.x.
void main() {
  late Directory tmp;
  late InProcessDb db;
  late NexServices services;
  late NexPreferences preferences;
  final committed = <String>[];

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_capture_typing_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    db = InProcessDb(
      dbPath: dbPath,
      deviceId: 'test',
      // Keep the first draft's id from landing mid-test: its arrival has
      // a rebuild of its own that is not what this file counts.
      captureDelay: const Duration(seconds: 30),
    );
    preferences = await NexPreferences.load();
    services = NexServices.forTest(
      worker: db,
      deviceId: 'test',
      preferences: preferences,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: p.join(tmp.path, 'media'),
      backupDir: p.join(tmp.path, 'backups'),
    );
    committed.clear();
  }

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> showSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CaptureSheet(
            services: services,
            preferences: preferences,
            onCamera: () {},
            onGallery: () {},
            onFile: () {},
            onCommitted: committed.add,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The sheet's chrome — everything `_CaptureSheetState.build` lays out and
  /// everything a keystroke used to rebuild.
  var chromeRebuilds = 0;
  void watchChrome() {
    chromeRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      switch (element.widget.runtimeType.toString()) {
        case '_KindBar':
        case '_ComposerBox':
        case '_ComposerFootnote':
        case '_Tool':
        case '_SideAction':
        case '_SendButton':
          chromeRebuilds++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
  }

  testWidgets('typing rebuilds the sheet only when the emptiness flips', (
    tester,
  ) async {
    await boot();
    await showSheet(tester);
    final field = nexInputs();
    expect(field, findsOneWidget);

    watchChrome();
    await enterNexText(tester, field, 'a');
    await tester.pump();
    final afterFirst = chromeRebuilds;
    expect(afterFirst, greaterThan(0), reason: 'empty → typed must rebuild');

    await enterNexText(tester, field, 'ab');
    await tester.pump();
    await enterNexText(tester, field, 'abc');
    await tester.pump();
    await enterNexText(tester, field, 'abcd');
    await tester.pump();
    expect(
      chromeRebuilds,
      afterFirst,
      reason: 'more typing changes nothing the sheet builds',
    );

    await enterNexText(tester, field, '');
    await tester.pump();
    final afterClear = chromeRebuilds;
    expect(afterClear, greaterThan(afterFirst), reason: 'typed → empty flips');

    await enterNexText(tester, field, '');
    await tester.pump();
    expect(
      chromeRebuilds,
      afterClear,
      reason: 'and staying empty rebuilds nothing',
    );

    // Let the deliberately-slow first-draft write and the sheet's own
    // debounce finish, so no timer outlives the tree.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('the flip-driven rebuilds still produce the working sheet', (
    tester,
  ) async {
    await boot();
    await showSheet(tester);
    final field = nexInputs();

    await enterNexText(tester, field, 'a note taking shape');
    await tester.pump();
    expect(find.byType(CaptureSheet), findsOneWidget);
    expect(nexInputController(tester, field).text, 'a note taking shape');

    await enterNexText(tester, field, '');
    await tester.pump();
    expect(find.byType(CaptureSheet), findsOneWidget);
    expect(nexInputs(), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });
}
