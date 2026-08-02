import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/os_capture_bridge.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/capture_sheet.dart';

import 'support/in_process_db.dart';

/// The widget deep links: a home-screen widget tap arrives at the timeline as
/// a queued event (cold start) or a live event, and both must end in the same
/// capture or navigation the in-app buttons drive. The widget itself used to
/// open the app and do nothing — the text_capture signal had no consumer.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_deeplink_');
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

  Future<void> pumpApp(WidgetTester tester, OsCaptureBridge bridge) async {
    await tester.pumpWidget(
      NexApp(
        services: services,
        preferences: preferences,
        osCapture: bridge,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a cold-start quick-capture tap opens the capture sheet', (
    tester,
  ) async {
    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);

    // The native side queues the tap before the engine is ready; the bridge
    // holds it until the timeline exists to consume it.
    await bridge.handle({'type': 'text_capture'});
    await pumpApp(tester, bridge);

    expect(find.byType(CaptureSheet), findsOneWidget);
  });

  testWidgets('a live quick-capture tap opens the capture sheet', (
    tester,
  ) async {
    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);

    await pumpApp(tester, bridge);
    expect(find.byType(CaptureSheet), findsNothing);

    await bridge.handle({'type': 'text_capture'});
    await tester.pumpAndSettle();

    expect(find.byType(CaptureSheet), findsOneWidget);
  });

  testWidgets('an open-note deep link opens that note', (tester) async {
    final note = (await services.captureText('deep linked note'))!;
    await services.refreshTimeline();

    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);

    await bridge.handle({'type': 'open_note', 'noteId': note.id});
    await pumpApp(tester, bridge);

    expect(find.byType(NoteDetailSheet), findsOneWidget);
    expect(find.text('deep linked note'), findsOneWidget);
  });

  testWidgets('an open-note deep link to a missing note does nothing', (
    tester,
  ) async {
    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);

    await bridge.handle({'type': 'open_note', 'noteId': 'no-such-note'});
    await pumpApp(tester, bridge);

    expect(find.byType(NoteDetailSheet), findsNothing);
    expect(find.byType(CaptureSheet), findsNothing);
  });

  testWidgets('widget events are queued in order and drained once', (
    tester,
  ) async {
    final bridge = OsCaptureBridge(services);
    addTearDown(bridge.dispose);

    await bridge.handle({'type': 'text_capture'});
    await bridge.handle({'type': 'open_note', 'noteId': 'nope'});

    final drained = bridge.takePendingUiEvents();
    expect(drained, hasLength(2));
    expect(drained[0]['type'], 'text_capture');
    expect(drained[1]['type'], 'open_note');
    expect(bridge.takePendingUiEvents(), isEmpty);
  });
}
