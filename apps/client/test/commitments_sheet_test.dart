import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/commitments_sheet.dart';

import 'support/in_process_db.dart';

/// The recurring page, which used to be a title, a plus and a list.
///
/// It was reachable only from Settings, which is where the app's own
/// configuration lives — and a list of somebody's bills and medication is
/// their data, not a preference. It has a place in the bar along the bottom
/// now, and this is the page that place opens.
void main() {
  late Directory tmp;
  late NexServices services;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_commitments_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // Straight to the worker, not through `services.saveCommitment`: that one
  // also schedules a real alarm, and this page never asks it to.
  Future<void> add(String title, DateTime due, {bool paused = false}) =>
      services.worker.saveCommitment(
        NexCommitment(
          id: 'c-$title',
          title: title,
          cadence: NexCadence.months,
          every: 1,
          dueAt: due,
          paused: paused,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

  Future<AppLocalizations> open(WidgetTester tester) async {
    // Tall, so the whole list is laid out. A `SliverList` only lays out what
    // the viewport reaches, and the ordering assertions below need to be
    // able to measure every row rather than the first three.
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: CommitmentsSheet(services: services)),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(
      tester.element(find.byType(CommitmentsSheet)),
    );
  }

  testWidgets('the page says what a recurring item is for', (tester) async {
    // It said nothing at all. A title, a plus and an empty list is a page
    // that only makes sense to whoever built it.
    final l10n = await open(tester);
    expect(find.text(l10n.commitmentsAbout), findsOneWidget);
  });

  testWidgets('an empty page invites rather than reports', (tester) async {
    final l10n = await open(tester);
    expect(find.text(l10n.commitmentsEmpty), findsOneWidget);
    // And no count beside the title, which would be a nought nobody needs.
    expect(find.text(l10n.commitmentsCount(0)), findsNothing);
  });

  testWidgets('what has slipped is at the top, whatever its date', (
    tester,
  ) async {
    final now = DateTime.now();
    // Deliberately out of date order relative to each other: sorted flat,
    // the overdue one would sit below both of the ones that are fine.
    await add('rent', now.subtract(const Duration(days: 9)));
    await add('insurance', now.add(const Duration(days: 2)));
    await add('passport', now.add(const Duration(days: 40)));
    await add('gym', now.add(const Duration(days: 5)), paused: true);

    final l10n = await open(tester);
    expect(find.text(l10n.commitmentsCount(4)), findsOneWidget);

    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y(l10n.commitmentsOverdue), lessThan(y('rent')));
    expect(y('rent'), lessThan(y(l10n.commitmentsComingUp)));
    expect(y(l10n.commitmentsComingUp), lessThan(y('insurance')));
    expect(y('insurance'), lessThan(y('passport')));
    expect(y('passport'), lessThan(y(l10n.commitmentsRested)));
    expect(y(l10n.commitmentsRested), lessThan(y('gym')));
  });

  testWidgets('a group with nothing in it is not drawn', (tester) async {
    await add('insurance', DateTime.now().add(const Duration(days: 2)));
    final l10n = await open(tester);
    expect(find.text(l10n.commitmentsComingUp), findsOneWidget);
    expect(find.text(l10n.commitmentsOverdue), findsNothing);
    expect(find.text(l10n.commitmentsRested), findsNothing);
  });
}
