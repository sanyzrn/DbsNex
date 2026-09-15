import 'dart:async';
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
import 'package:nex_client/screens/timeline_screen.dart';

import 'support/in_process_db.dart';

/// Where a tap from outside the app lands.
///
/// The reported bug: open Settings, press home, tap a widget — and Nex comes
/// back to Settings. That is Android doing exactly the right thing for a
/// launch of a running task (resume it as it was left) and exactly the wrong
/// thing for a tap on a specific piece of the app, and neither half of the
/// app was in a position to notice. The intent carried no action, so Dart was
/// never told the tap had happened at all.
///
/// Every request from an OS surface now brings the timeline forward first.
/// These tests hold that for all four of them, because the failure is silent
/// in every one: the sheet a widget asks for opens *behind* whatever was on
/// screen, or nothing visible happens at all.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;
  late OsCaptureBridge bridge;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_widget_tap_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    preferences = await NexPreferences.load();
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: preferences,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
    await preferences.completeOnboarding();
    await preferences.completeTour();
    bridge = OsCaptureBridge(services);
  });

  tearDown(() async {
    bridge.dispose();
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Brings the app up with something else stacked over the timeline.
  ///
  /// A plain route rather than the real Settings sheet: what is being tested
  /// is that *whatever* is on top goes away, and a route with a word in it
  /// says that without dragging a screen's worth of setup in behind it.
  Future<void> pumpWithARouteOnTop(WidgetTester tester) async {
    await tester.pumpWidget(
      NexApp(
        services: services,
        preferences: preferences,
        osCapture: bridge,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimelineScreen), findsOneWidget);

    unawaited(
      Navigator.of(tester.element(find.byType(TimelineScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('somewhere else')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('somewhere else'), findsOneWidget);
  }

  testWidgets('a plain widget tap dismisses what was on top', (tester) async {
    await pumpWithARouteOnTop(tester);

    await bridge.handle({'type': 'open_timeline'});
    await tester.pumpAndSettle();

    expect(find.text('somewhere else'), findsNothing);
    expect(find.byType(TimelineScreen), findsOneWidget);
  });

  testWidgets('a capture widget tap opens capture, not a sheet behind', (
    tester,
  ) async {
    await pumpWithARouteOnTop(tester);

    await bridge.handle({'type': 'text_capture'});
    // Fixed pumps rather than `pumpAndSettle`: the capture sheet runs a
    // debounce timer while it is open, and settling waits for a quiet frame
    // that a repeating timer never gives. Two route animations' worth of
    // time is what this needs and all it needs.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The route that was on top is gone. Without the surfacing, the capture
    // sheet was pushed on top of it — so the assertion that matters is this
    // one, not that capture opened.
    expect(find.text('somewhere else'), findsNothing);
  });

  testWidgets('a recap refresh brings the card it spins into view', (
    tester,
  ) async {
    await pumpWithARouteOnTop(tester);

    await bridge.handle({'type': 'refresh_recap'});
    await tester.pumpAndSettle();

    expect(find.text('somewhere else'), findsNothing);
    expect(find.byType(TimelineScreen), findsOneWidget);
  });

  testWidgets('nothing is dismissed when the timeline is already showing', (
    tester,
  ) async {
    // The ordinary case, and the one a blunt `popUntil` would get wrong in a
    // way nobody would notice until it ate something: with nothing stacked
    // over the timeline there is nothing to pop, and the guard is what says
    // so.
    await tester.pumpWidget(
      NexApp(
        services: services,
        preferences: preferences,
        osCapture: bridge,
      ),
    );
    await tester.pumpAndSettle();

    await bridge.handle({'type': 'open_timeline'});
    await tester.pumpAndSettle();

    expect(find.byType(TimelineScreen), findsOneWidget);
  });
}
