import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';

import 'support/in_process_db.dart';

/// Reported symptom: on a phone set to three-button navigation, the bottom of
/// a sheet ran under the navigation bar; on the same phone using gesture
/// navigation it looked right.
///
/// `showModalBottomSheet(useSafeArea: true)` reads as if it covers this and
/// does not — Flutter applies `SafeArea(bottom: false)` for that flag, and its
/// own documentation says the sheet "extends all the way to the bottom of the
/// screen, including any system intrusions". Gesture navigation reserves so
/// little that the overlap passes for padding; three buttons reserve about
/// 48dp, and the sheet's last control lands underneath them.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  /// What Android reports for a three-button navigation bar.
  const navBar = 48.0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_sheet_inset_');
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

  testWidgets('a sheet ends above a three-button navigation bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);
    addTearDown(tester.view.reset);

    await services.captureText('a note to open');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('a note to open'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteDetailSheet), findsOneWidget);

    // Delete is the sheet's last control, so it is the one that lands under
    // the navigation bar when the bottom inset is not reserved.
    final delete = tester.getRect(find.text('Delete'));
    expect(
      delete.bottom,
      lessThanOrEqualTo(900 - navBar),
      reason: "the sheet's last control must end above the navigation bar",
    );
  });
}
