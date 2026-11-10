import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/screens/timeline/timeline_model.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// No-op database reads must not repaint the timeline. Real changes to notes,
/// reminder metadata, tags and AI enrichment must never be hidden by this
/// optimization — including changes outside the current filter.
void main() {
  group('TimelineModel no-op refresh', () {
    late NexTestHarness harness;
    late TimelineModel model;
    var rebuilds = 0;
    var deliveries = 0;

    Future<void> refreshed() async {
      await harness.services.refreshTimeline();
      // A broadcast stream's asynchronous delivery follows the DB future.
      await Future<void>.delayed(Duration.zero);
    }

    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_noop_model_');
      model = TimelineModel(
        services: harness.services,
        preferences: harness.preferences,
      );
      rebuilds = 0;
      deliveries = 0;
      model.addListener(() => rebuilds++);
      model.listen((_) => deliveries++);
    });

    tearDown(() async {
      model.dispose();
      await harness.dispose();
    });

    test('no-op delivery skips redundant work', () async {
      await harness.services.captureText('the only note');
      await model.load();
      final before = rebuilds;
      await refreshed();
      await refreshed();
      expect(rebuilds, before);
      expect(deliveries, 0);
      expect(model.notes, hasLength(1));
    });

    test('new note still triggers a delivery', () async {
      await harness.services.captureText('first');
      await model.load();
      final before = rebuilds;
      await harness.services.captureText('second');
      await refreshed();
      expect(rebuilds, greaterThan(before));
      expect(deliveries, greaterThan(0));
      expect(model.notes.map((n) => n.content), contains('second'));
    });

    test('pin and reminder updates still notify', () async {
      final note = (await harness.services.captureText('to pin'))!;
      await model.load();
      final before = rebuilds;
      expect(await harness.services.pinNote(note.id), isTrue);
      await refreshed();
      expect(rebuilds, greaterThan(before));
      expect(model.byId(note.id)!.pinnedAt, isNotNull);

      final afterPin = rebuilds;
      final due = DateTime.now().add(const Duration(days: 2));
      await harness.services.setDueAt(note.id, due);
      await refreshed();
      expect(rebuilds, greaterThan(afterPin));
      expect(model.byId(note.id)!.dueAt, isNotNull);
    });

    test('AI summary changes without rev bump notify', () async {
      final note = (await harness.services.captureText('original'))!;
      await model.load();
      final before = model.byId(note.id)!;
      final seen = rebuilds;
      await harness.db.setSummaryText(note.id, 'new summary');
      await refreshed();
      final current = model.byId(note.id)!;
      expect(current.rev, before.rev);
      expect(current.updatedAt, before.updatedAt);
      expect(current.summaryText, 'new summary');
      expect(rebuilds, greaterThan(seen));
    });

    test('transcription and OCR without rev bump notify', () async {
      final note = (await harness.services.captureText('original'))!;
      await model.load();
      final before = model.byId(note.id)!;
      final seen = rebuilds;
      harness.db.seedTranscript(note.id, 'converted speech');
      await refreshed();
      expect(model.byId(note.id)!.transcriptText, 'converted speech');
      expect(rebuilds, greaterThan(seen));

      final seenAgain = rebuilds;
      harness.db.seedReadText(note.id, 'image text');
      await refreshed();
      expect(model.byId(note.id)!.ocrText, 'image text');
      expect(model.byId(note.id)!.rev, before.rev);
      expect(rebuilds, greaterThan(seenAgain));
    });

    test('tag chips update the displayed cards in the same notification', () async {
      final workNote = (await harness.services.captureText('work only'))!;
      final homeNote = (await harness.services.captureText('home only'))!;
      final work = await harness.services.addTag(
        noteId: workNote.id,
        name: 'Work',
      );
      final home = await harness.services.addTag(
        noteId: homeNote.id,
        name: 'Home',
      );
      await model.load();

      // The old implementation notified listeners before applying the tag
      // filter, then suppressed the second notification because the raw
      // timeline rows had not changed. The next tap appeared to reveal the
      // previous selection, just as in the reported screen recording.
      final painted = <List<String>>[];
      model.addListener(() {
        painted.add([for (final note in model.notes) note.id]);
      });

      await model.selectTags({work.id});
      expect(model.notes.map((n) => n.id), [workNote.id]);
      expect(painted.last, [workNote.id]);

      await model.selectTags({home.id});
      expect(model.notes.map((n) => n.id), [homeNote.id]);
      expect(painted.last, [homeNote.id]);

      await model.selectTags({work.id, home.id});
      expect(model.notes.map((n) => n.id).toSet(), {
        workNote.id,
        homeNote.id,
      });
      expect(painted.last.toSet(), {workNote.id, homeNote.id});

      await model.clearFilters();
      expect(model.selectedTagIds, isEmpty);
      expect(painted.last.toSet(), {workNote.id, homeNote.id});

      final first = model.selectTags({work.id});
      final second = model.selectTags({home.id});
      await Future.wait([first, second]);
      expect(painted.last, [homeNote.id],
          reason: 'quick taps must never repaint an older selection');
    });

    test('hidden note updates still reach the recap', () async {
      final tagged = (await harness.services.captureText('shown'))!;
      final hidden = (await harness.services.captureText('hidden'))!;
      final tag = await harness.services.addTag(
        noteId: tagged.id,
        name: 'work',
      );
      await model.load();
      await model.selectTags({tag.id});
      expect(model.notes.map((n) => n.id), [tagged.id]);

      final seen = rebuilds;
      final heard = deliveries;
      await harness.db.setSummaryText(hidden.id, 'hidden note now summarized');
      await refreshed();
      // Visible cards remain filtered, but the unfiltered snapshot and recap
      // still receive the underlying note change.
      expect(model.notes.map((n) => n.id), [tagged.id]);
      expect(model.byId(hidden.id)!.summaryText, 'hidden note now summarized');
      expect(rebuilds, greaterThan(seen));
      expect(deliveries, greaterThan(heard));
    });

    test('tag name, color and count updates notify', () async {
      final note = (await harness.services.captureText('tagged'))!;
      final tag = await harness.services.addTag(noteId: note.id, name: 'work');
      await model.loadFilterTags();
      final before = rebuilds;
      await model.loadFilterTags();
      expect(rebuilds, before);

      await harness.services.setTagColor(tagId: tag.id, color: '#bb3366');
      await model.loadFilterTags();
      expect(rebuilds, greaterThan(before));
      expect(model.filterTags.single.color, '#bb3366');

      final next = rebuilds;
      final second = (await harness.services.captureText('another'))!;
      await harness.services.addTag(noteId: second.id, name: 'work');
      await model.loadFilterTags();
      expect(model.filterTagCounts[tag.id], 2);
      expect(rebuilds, greaterThan(next));
    });

    test('reloading unchanged commitments avoids a rebuild', () async {
      final day = DateTime(2026, 11, 9, 12);
      final due = day.add(const Duration(days: 9));
      await harness.services.worker.saveCommitment(
        NexCommitment(
          id: 'c-rent',
          title: 'Rent',
          cadence: NexCadence.months,
          every: 1,
          dueAt: due,
          createdAt: day,
          updatedAt: day,
        ),
      );
      await model.loadCommitments(now: day);
      expect(model.commitments, hasLength(1));
      final seen = rebuilds;
      await model.loadCommitments(now: day);
      await model.loadCommitments(now: day);
      expect(rebuilds, seen);
    });

    test('a changed commitment flag still notifies', () async {
      final day = DateTime(2026, 11, 9, 12);
      final due = day.add(const Duration(days: 9));
      NexCommitment rent({bool paused = false}) => NexCommitment(
        id: 'c-rent',
        title: 'Rent',
        cadence: NexCadence.months,
        every: 1,
        dueAt: due,
        createdAt: day,
        updatedAt: day,
        paused: paused,
      );
      await harness.services.worker.saveCommitment(rent());
      await model.loadCommitments(now: day);
      final seen = rebuilds;
      // No rev or updatedAt change: the field itself must be detected.
      await harness.services.worker.saveCommitment(rent(paused: true));
      await model.loadCommitments(now: day);
      expect(rebuilds, greaterThan(seen));
      expect(model.commitments.single.paused, isTrue);
    });

    test('nested details changes notify, equal maps do not', () async {
      final day = DateTime(2026, 11, 9, 12);
      NexCommitment rent(Map<String, dynamic> details) => NexCommitment(
        id: 'c-rent',
        title: 'Rent',
        cadence: NexCadence.months,
        every: 1,
        dueAt: day.add(const Duration(days: 9)),
        createdAt: day,
        updatedAt: day,
        details: details,
      );
      await harness.services.worker.saveCommitment(
        rent({
          'amountMinor': 2000,
          'history': [
            {
              'action': 'done',
              'receipt': {'reference': 'A'},
            },
          ],
        }),
      );
      await model.loadCommitments(now: day);
      final before = rebuilds;
      // Reordering map keys does not change its meaning.
      await harness.services.worker.saveCommitment(
        rent({
          'history': [
            {
              'receipt': {'reference': 'A'},
              'action': 'done',
            },
          ],
          'amountMinor': 2000,
        }),
      );
      await model.loadCommitments(now: day);
      expect(rebuilds, before);
      // Nested receipt edit, without rev or updatedAt bump, must be visible.
      await harness.services.worker.saveCommitment(
        rent({
          'amountMinor': 2000,
          'history': [
            {
              'action': 'done',
              'receipt': {'reference': 'B'},
            },
          ],
        }),
      );
      await model.loadCommitments(now: day);
      expect(rebuilds, greaterThan(before));
      expect(model.commitments.single.history.single['receipt'], {
        'reference': 'B',
      });
    });

    test('local midnight refreshes completion counts exactly once', () async {
      final yesterday = DateTime(2026, 11, 8, 23, 59);
      final today = DateTime(2026, 11, 9, 0, 1);
      await harness.services.worker.saveCommitment(
        NexCommitment(
          id: 'c-water',
          title: 'Water',
          cadence: NexCadence.hours,
          every: 2,
          dueAt: today.add(const Duration(hours: 2)),
          createdAt: yesterday,
          updatedAt: yesterday,
          metToday: 3,
          metTodayOn: nexDayKey(yesterday),
        ),
      );
      await model.loadCommitments(now: yesterday);
      expect(model.commitments.single.metOn(yesterday), 3);
      final before = rebuilds;
      await model.loadCommitments(now: yesterday);
      expect(rebuilds, before);
      await model.loadCommitments(now: today);
      expect(rebuilds, before + 1);
      expect(model.commitments.single.metOn(today), 0);
      await model.loadCommitments(now: today);
      expect(rebuilds, before + 1);
    });
  });

  group('return animations', () {
    late NexTestHarness harness;
    var cardRebuilds = 0;

    void watchCardRebuilds() {
      cardRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is NoteCard) cardRebuilds++;
      };
    }

    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_noop_return_');
      await harness.services.captureText('a plain note');
      await harness.services.refreshTimeline();
    });

    tearDown(() async {
      debugOnRebuildDirtyWidget = null;
      await harness.dispose();
    });

    testWidgets('read-only note close does not rebuild cards', (tester) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NoteCard).first);
      await tester.pumpAndSettle();
      expect(find.byType(NoteDetailSheet), findsOneWidget);

      watchCardRebuilds();
      Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(NoteDetailSheet), findsNothing);
      // Navigator can naturally rebuild one inherited-route dependent card;
      // the optimization must prevent the extra full-list rebuild.
      expect(cardRebuilds, lessThanOrEqualTo(1));
    });

    testWidgets('unchanged page return does not rebuild cards', (tester) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      final nav = Navigator.of(tester.element(find.byType(TimelineScreen)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      watchCardRebuilds();
      nav.pop();
      await tester.pumpAndSettle();

      // Navigator can naturally rebuild one inherited-route dependent card;
      // the optimization must prevent the extra full-list rebuild.
      expect(cardRebuilds, lessThanOrEqualTo(1));
    });

    testWidgets('covered settings changes still apply', (tester) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      final nav = Navigator.of(tester.element(find.byType(TimelineScreen)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final prefs = harness.preferences;
      await prefs.setAiEnabled(!prefs.aiEnabled);
      await tester.pumpAndSettle();
      nav.pop();
      await tester.pumpAndSettle();

      // Even if the settings listener already applied it while covered,
      // route return must not leave an out-of-date home screen.
      expect(find.byType(TimelineScreen), findsOneWidget);
      expect(find.byType(NoteCard), findsWidgets);
    });
  });
}
