import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline/timeline_model.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_process_db.dart';
import 'support/nex_harness.dart';

/// The timeline's rebuild discipline: what it reuses when a change moves no
/// note, what still repaints on a tags or commitments change, what a nested
/// scroll is not allowed to do to the list around it, and that a delivery
/// under a scrolled list re-derives the sticky day.
void main() {
  Finder card(String id) =>
      find.byWidgetPredicate((w) => w is NoteCard && w.note.id == id);
  TimelineScreenState timeline(WidgetTester tester) =>
      tester.state(find.byType(TimelineScreen));

  /// The date the sticky-day chip shows once settled, or null while it is
  /// tucked away — the same reading the sticky day's own test uses.
  String? shownDay(WidgetTester tester) {
    final text = find.descendant(
      of: find.byType(TimelineStickyDay),
      matching: find.byType(Text),
    );
    if (text.evaluate().isEmpty) return null;
    return tester.widget<Text>(text.last).data;
  }

  /// A screen with its chrome quiet: no greeting, no recap, so what is on
  /// screen is the cards and the filter row and nothing else.
  Future<NexTestHarness> open(WidgetTester tester) async {
    final h = await NexTestHarness.create(name: 'nex_rows_');
    addTearDown(h.dispose);
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await h.preferences.setShowGreeting(false);
    await h.preferences.setShowTagRow(true);
    return h;
  }

  testWidgets('a change that moves no note reuses the built rows', (
    tester,
  ) async {
    final h = await open(tester);
    await h.preferences.setShowDaySummary(false);
    final note = (await h.services.captureText('the note'))!;
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final built = timeline(tester).debugRowBuilds;
    expect(built, greaterThan(0));

    // A ringing change repaints the screen's own state without touching a
    // note: the cards' rows — the grouping, the wrappers, the list diff —
    // are reused rather than walked again.
    h.services.ringing.value = {note.id};
    await tester.pumpAndSettle();
    expect(timeline(tester).debugRowBuilds, built);
    h.services.ringing.value = const {};
    await tester.pumpAndSettle();
    expect(timeline(tester).debugRowBuilds, built);
    expect(card(note.id), findsOneWidget);

    // A delivery that changed the notes rebuilds them — the cache is a
    // memo, not a latch.
    await h.services.captureText('a second note');
    await h.services.refreshTimeline();
    await tester.pumpAndSettle();
    expect(timeline(tester).debugRowBuilds, greaterThan(built));
    expect(card(note.id), findsOneWidget);
  });

  testWidgets('a tags refresh repaints the row, not the cards', (tester) async {
    final h = await open(tester);
    final note = (await h.services.captureText('to tag'))!;
    final tag = await h.services.addTag(noteId: note.id, name: 'work');
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final built = timeline(tester).debugRowBuilds;
    final cardElement = tester.element(card(note.id));

    // A rename the notes themselves never hear about: the stream is not
    // fired, so the tag read is the only thing that can notice it. It
    // repaints the row (the pill says the new name) without reassembling
    // the rows or rebuilding the card for it.
    await h.db.renameTag(tag.id, 'renamed work');
    await timeline(tester).model.loadFilterTags();
    await tester.pumpAndSettle();

    expect(find.text('renamed work'), findsOneWidget);
    expect(timeline(tester).debugRowBuilds, built);
    expect(tester.element(card(note.id)), same(cardElement));
  });

  testWidgets('a commitments read repaints the brief, not the cards', (
    tester,
  ) async {
    final h = await open(tester);
    // The report style writes its own lines and needs no provider.
    await h.preferences.setShowDaySummary(true);
    await h.preferences.setBriefStyle(NexBriefStyle.report);
    final note = (await h.services.captureText('a plain day'))!;
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final built = timeline(tester).debugRowBuilds;
    final cardElement = tester.element(card(note.id));
    expect(find.byKey(const ValueKey('timeline-recap')), findsOneWidget);

    final day = DateTime(2026, 1, 20);
    NexCommitment rent() => NexCommitment(
      id: 'c-rent',
      title: 'Rent',
      cadence: NexCadence.months,
      every: 1,
      dueAt: DateTime(2026, 2, 1),
      createdAt: day,
      updatedAt: day,
    );
    await h.services.worker.saveCommitment(rent());
    await timeline(tester).model.loadCommitments(now: day);
    await tester.pumpAndSettle();

    // The card was not rebuilt for the brief's own data...
    expect(timeline(tester).debugRowBuilds, built);
    expect(tester.element(card(note.id)), same(cardElement));
    // ...and the brief itself still noticed, through its own ear on the
    // model rather than a whole-screen rebuild.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-recap')),
        matching: find.textContaining('Rent'),
      ),
      findsWidgets,
    );
  });

  testWidgets('dragging the tag row sideways leaves the list alone', (
    tester,
  ) async {
    final h = await open(tester);
    await h.preferences.setShowDaySummary(true);
    await h.preferences.setBriefStyle(NexBriefStyle.report);
    final first = (await h.services.captureText('tag me'))!;
    for (var i = 0; i < 12; i++) {
      await h.services.captureText('note $i');
    }
    // Ten tags across the notes (three is a note's cap): enough pills to
    // make the row wider than the screen and worth dragging.
    for (var i = 0; i < 10; i++) {
      await h.services.addTag(
        noteId: i == 0
            ? first.id
            : (await h.services.captureText('carrier $i'))!.id,
        name: 'a very long tag name number $i',
      );
    }
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    // The recap's body is on screen to begin with.
    final recapText = find.descendant(
      of: find.byKey(const ValueKey('timeline-recap')),
      matching: find.byType(Text),
    );
    final before = tester.widgetList<Text>(recapText).length;
    expect(before, greaterThan(0));

    // A horizontal drag along the tag row used to arrive at the timeline's
    // own scroll listeners with the row's metrics: it collapsed the recap
    // and asked the window for pages it did not need. Now it is none of the
    // timeline's business.
    final row = find.descendant(
      of: find.byType(TagFilterRow),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.timedDrag(
      row,
      const Offset(-160, 0),
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();
    expect(tester.widgetList<Text>(recapText).length, before);
    expect(h.services.timelineWindow, NexServices.timelineBaseWindow);
  });

  testWidgets('a delivery under a scrolled list re-derives the sticky day', (
    tester,
  ) async {
    final h = await open(tester);
    // Twenty notes, each on its own day: whatever the chip names, deleting
    // the note under the line must change what it names.
    final db = NexDatabase.open(h.dbPath);
    final start = DateTime.now().toUtc().subtract(const Duration(days: 40));
    db.db.execute('BEGIN IMMEDIATE');
    for (var i = 0; i < 20; i++) {
      final at = start.add(Duration(days: i)).toIso8601String();
      db.db.execute(
        'INSERT INTO notes (id, type, content, created_at, updated_at, '
        "device_id, rev, sync_state) VALUES (?, 'text', ?, ?, ?, 't', 1, "
        "'synced')",
        ['n$i', 'note number $i', at, at],
      );
    }
    db.db.execute('COMMIT');
    db.close();
    await h.services.refreshTimeline();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(shownDay(tester), isNull, reason: 'at the top the headings say it');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final before = shownDay(tester);
    expect(before, isNotNull);

    // Which note's card is the one passing under the filter row: the
    // topmost card whose box reaches past the chip's own line.
    final chipTop = tester.getTopLeft(find.byType(TimelineStickyDay)).dy;
    String? underLine;
    var best = double.infinity;
    for (final element in find.byType(NoteCard).evaluate()) {
      final box = element.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = tester.getTopLeft(find.byWidget(element.widget)).dy;
      if (top + box.size.height <= chipTop) continue;
      if (top < best) {
        best = top;
        underLine = (element.widget as NoteCard).note.id;
      }
    }
    expect(underLine, isNotNull, reason: 'a card is passing under the line');

    await h.services.deleteNote(underLine!);
    await h.services.refreshTimeline();
    await tester.pumpAndSettle();

    // The next card's day takes the chip's place without a scroll having
    // moved — the delivery re-derives it post-frame.
    expect(shownDay(tester), isNot(before));
  });

  test('two tag reads in flight are one query', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('nex_flight_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final db = _CountingDb(
      dbPath: p.join(tmp.path, 'nex.sqlite'),
      deviceId: 'test',
    );
    final preferences = await NexPreferences.load();
    final services = NexServices.forTest(
      worker: db,
      deviceId: 'test',
      preferences: preferences,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: p.join(tmp.path, 'nex.sqlite'),
      mediaDir: p.join(tmp.path, 'media'),
      backupDir: p.join(tmp.path, 'backups'),
    );
    addTearDown(services.dispose);
    final model = TimelineModel(services: services, preferences: preferences);
    addTearDown(model.dispose);

    // Called back to back, before the first read can resolve: one query
    // serves both.
    await Future.wait<void>([model.loadFilterTags(), model.loadFilterTags()]);
    expect(db.tagUsageCalls, 1);
    await model.loadFilterTags();
    expect(db.tagUsageCalls, 2);
  });
}

/// Counts tag queries, so a coalescing test can see what actually ran.
class _CountingDb extends InProcessDb {
  _CountingDb({required super.dbPath, required super.deviceId});

  int tagUsageCalls = 0;

  @override
  Future<List<TagUsage>> tagUsage({bool timelineOnly = false}) async {
    tagUsageCalls++;
    return super.tagUsage(timelineOnly: timelineOnly);
  }
}
