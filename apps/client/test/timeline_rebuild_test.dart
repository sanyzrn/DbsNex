import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/commit_receipt.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/empty_timeline.dart';

import 'support/in_process_db.dart';

/// What the timeline promises after the rebuild: it never lies about being
/// empty, it confirms a capture landed, it finds things without leaving, and
/// its chrome lines up with its content on a wide window.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  Future<NexServices> build(Directory dir, {Duration? delay}) async {
    final dbPath = p.join(dir.path, 'nex.sqlite');
    final mediaDir = p.join(dir.path, 'media');
    final backupDir = p.join(dir.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    return NexServices.forTest(
      worker: InProcessDb(
        dbPath: dbPath,
        deviceId: 'test',
        readDelay: delay,
      ),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_timeline_');
    services = await build(tmp);
    preferences = await NexPreferences.load();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('a cold launch with notes never flashes the onboarding screen',
      (tester) async {
    await services.captureText('something already here');
    // Deliberately slow, so the "not loaded yet" state lasts long enough to
    // observe. `_all` was `const []` at field initialisation, which satisfies
    // "empty" — so every cold launch showed a user with a full library the
    // "capture in seconds" onboarding copy before their notes painted.
    final slow = await build(tmp, delay: const Duration(milliseconds: 300));
    addTearDown(slow.dispose);

    await tester.pumpWidget(NexApp(services: slow, preferences: preferences));
    await tester.pump();

    expect(find.byType(EmptyTimeline), findsNothing);
    expect(find.byType(NexCardSkeleton), findsWidgets);

    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.byType(NexCardSkeleton), findsNothing);
    expect(find.text('something already here'), findsOneWidget);
  });

  testWidgets('a genuinely empty library still gets the onboarding screen',
      (tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyTimeline), findsOneWidget);
  });

  testWidgets('a captured note gets a receipt that clears itself',
      (tester) async {
    await services.captureText('older');
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final timeline = tester.state<TimelineScreenState>(
      find.byType(TimelineScreen),
    );

    final note = (await services.captureText('just written'))!;
    timeline.markLanded(note.id);
    await services.refreshTimeline();
    await tester.pump();

    final active = tester
        .widgetList<CommitReceipt>(find.byType(CommitReceipt))
        .where((r) => r.active);
    expect(active.length, 1, reason: 'exactly one note is the new one');

    // And it is a moment, not a mark: the id used to be set and never cleared,
    // so the last captured note stayed nudged for the life of the widget.
    await tester.pumpAndSettle();
    expect(timeline.landedId, isNull);
  });

  testWidgets('search happens on the timeline, without pushing a route',
      (tester) async {
    for (var i = 0; i < 10; i++) {
      await services.captureText('filler $i');
    }
    await services.captureText('a note about rockets');
    await services.captureText('a note about bread');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // Genuinely gone at rest, not merely clipped: the header collapses to zero
    // extent, so its subtree is not built at all.
    final field = find.byType(TextField);
    expect(field, findsNothing);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    // Same route. Search used to be a full-screen push behind this icon, which
    // put half the tagline a transition away from the list it searches.
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(field, findsOneWidget);
    expect(
      tester.getRect(field).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(CustomScrollView)).top - 1),
    );

    await tester.enterText(field, 'rockets');
    await tester.pumpAndSettle();
    expect(find.text('a note about rockets'), findsOneWidget);
    expect(find.text('a note about bread'), findsNothing);
  });

  testWidgets('a library too short to scroll simply shows the field',
      (tester) async {
    await services.captureText('the only note');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // With nothing to scroll there is nowhere to hide it, and that is the
    // honest outcome rather than a bug: with one note, search is right there.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('pulling the timeline down brings the search field in',
      (tester) async {
    for (var i = 0; i < 12; i++) {
      await services.captureText('note $i');
    }
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    final list = find.byType(CustomScrollView);
    expect(field, findsNothing, reason: 'out of sight at rest');

    // Pull down: the field is part of the list, above the first card, so this
    // is ordinary scrolling — which is why it behaves the same under Android's
    // clamping physics and iOS's bouncing ones.
    await tester.drag(list, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);

    // And scrolling on takes it away again, the way iOS Mail's does.
    await tester.drag(list, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(field, findsNothing);

    // How the half-open snap *feels* is a device check, not a widget test —
    // the offsets are assertable, the spring is not.
  });

  testWidgets('the filter row and the cards share one edge on a wide window',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await services.captureText('a note');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // The filter row used to be a sibling *above* the 760px column, so on a
    // wide window the pills started at the window edge and the cards did not.
    final row = tester.getRect(find.byType(TagFilterRow));
    final card = tester.getRect(find.byType(NoteCard));
    expect(row.left, greaterThan(0));
    expect(row.width, lessThanOrEqualTo(760));
    expect(row.center.dx, closeTo(card.center.dx, 1));
  });
}
