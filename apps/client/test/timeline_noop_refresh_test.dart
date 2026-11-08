import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/screens/timeline/timeline_model.dart';
import 'package:nex_client/screens/timeline_screen.dart';
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
      await harness.services.refreshTimeline();
      await harness.services.refreshTimeline();
      expect(rebuilds, before);
      expect(deliveries, 0);
      expect(model.notes, hasLength(1));
    });

    test('new note still triggers a delivery', () async {
      await harness.services.captureText('first');
      await model.load();
      final before = rebuilds;
      await harness.services.captureText('second');
      await harness.services.refreshTimeline();
      expect(rebuilds, greaterThan(before));
      expect(deliveries, greaterThan(0));
      expect(model.notes.map((n) => n.content), contains('second'));
    });

    test('pin and reminder updates still notify', () async {
      final note = (await harness.services.captureText('to pin'))!;
      await model.load();
      final before = rebuilds;
      expect(await harness.services.pinNote(note.id), isTrue);
      await harness.services.refreshTimeline();
      expect(rebuilds, greaterThan(before));
      expect(model.byId(note.id)!.pinnedAt, isNotNull);

      final afterPin = rebuilds;
      final due = DateTime.now().add(const Duration(days: 2));
      await harness.services.setDueAt(note.id, due);
      await harness.services.refreshTimeline();
      expect(rebuilds, greaterThan(afterPin));
      expect(model.byId(note.id)!.dueAt, isNotNull);
    });

    test('AI summary changes without rev bump notify', () async {
      final note = (await harness.services.captureText('original'))!;
      await model.load();
      final before = model.byId(note.id)!;
      final seen = rebuilds;
      await harness.db.setSummaryText(note.id, 'new summary');
      await harness.services.refreshTimeline();
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
      await harness.services.refreshTimeline();
      expect(model.byId(note.id)!.transcriptText, 'converted speech');
      expect(rebuilds, greaterThan(seen));

      final seenAgain = rebuilds;
      harness.db.seedReadText(note.id, 'image text');
      await harness.services.refreshTimeline();
      expect(model.byId(note.id)!.ocrText, 'image text');
      expect(model.byId(note.id)!.rev, before.rev);
      expect(rebuilds, greaterThan(seenAgain));
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
      await harness.services.refreshTimeline();
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
      expect(cardRebuilds, 0);
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

      expect(cardRebuilds, 0);
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
