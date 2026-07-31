import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/settings_sheet.dart';

import 'support/in_process_db.dart';

/// Reported symptom: a fast fling starting from the bottom of Settings could
/// cross the whole scroll range and bounce past the top in one motion — the
/// same ballistic overshoot the existing dismiss-on-overscroll relies on to
/// detect a genuine downward drag at the top — closing the sheet on the way
/// there instead of merely scrolling it. A real drag once it has actually
/// arrived at the top must still close it.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_settings_dismiss_');
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
    await preferences.setReduceMotion(true);
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Dispatches a synthetic [OverscrollNotification] through the settings
  /// sheet's real scroll view, the same one the widget's own
  /// `NotificationListener` reacts to — this is what lets the two scenarios
  /// below be deterministic instead of depending on a scroll physics
  /// simulation to overshoot by the right amount at the right moment.
  void dispatchOverscroll(WidgetTester tester, {required bool fromDrag}) {
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    final position = scrollable.position;
    OverscrollNotification(
      metrics: position.copyWith(),
      context: scrollable.context,
      overscroll: -20,
      dragDetails: fromDrag
          ? DragUpdateDetails(globalPosition: Offset.zero)
          : null,
    ).dispatch(scrollable.context);
  }

  testWidgets('a fling settling past the top does not close Settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsOneWidget);

    // dragDetails: null — a ballistic simulation settling past the
    // boundary, not a finger on the glass.
    dispatchOverscroll(tester, fromDrag: false);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSheet), findsOneWidget);
  });

  testWidgets('a real drag past the top closes Settings', (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSheet), findsOneWidget);

    dispatchOverscroll(tester, fromDrag: true);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSheet), findsNothing);
  });
}
