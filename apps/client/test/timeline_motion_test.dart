import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  Finder card(String id) =>
      find.byWidgetPredicate((w) => w is NoteCard && w.note.id == id);
  TimelineScreenState timeline(WidgetTester tester) =>
      tester.state(find.byType(TimelineScreen));

  Future<NexTestHarness> open(
    WidgetTester tester, {
    bool reduced = false,
  }) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduced);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await h.preferences.setShowGreeting(false);
    await h.preferences.setShowDaySummary(false);
    return h;
  }

  for (final reduced in [false, true]) {
    testWidgets('deletion shrinks out, undo restores it, reduced=$reduced', (
      tester,
    ) async {
      final h = await open(tester, reduced: reduced);
      final deleted = (await h.services.captureText('Delete me'))!;
      final kept = (await h.services.captureText('Keep me'))!;
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final keptElement = tester.element(card(kept.id));
      await timeline(tester).deleteWithUndo(deleted);
      await tester.pump();
      expect(await h.services.getById(deleted.id), isNull);
      if (!reduced) {
        expect(
          card(deleted.id),
          findsOneWidget,
          reason: 'only the departing preview remains',
        );
        await tester.pump(const Duration(milliseconds: 90));
        final sizes = tester.widgetList<SizeTransition>(
          find.ancestor(
            of: card(deleted.id),
            matching: find.byType(SizeTransition),
          ),
        );
        expect(
          sizes.any(
            (size) => size.sizeFactor.value > 0 && size.sizeFactor.value < 1,
          ),
          isTrue,
        );
      }
      await tester.pumpAndSettle();
      expect(card(deleted.id), findsNothing);
      expect(
        tester.element(card(kept.id)),
        same(keptElement),
        reason: 'unchanged cards keep their state',
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TimelineScreen)),
      );
      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();
      expect(card(deleted.id), findsOneWidget);
      expect((await h.services.getById(deleted.id))?.deletedAt, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'pin/unpin and rapid filters settle to the correct cards, reduced=$reduced',
      (tester) async {
        final h = await open(tester, reduced: reduced);
        final notes = <Note>[];
        for (var i = 0; i < 5; i++) {
          notes.add((await h.services.captureText('Note $i'))!);
        }
        final work = await h.services.addTag(noteId: notes[0].id, name: 'work');
        final home = await h.services.addTag(noteId: notes[1].id, name: 'home');
        await h.services.refreshTimeline();
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        await h.services.pinNote(notes[0].id);
        await h.services.refreshTimeline();
        await tester.pumpAndSettle();
        expect(timeline(tester).model.notes.first.id, notes[0].id);
        expect(card(notes[0].id), findsOneWidget);
        await h.services.unpinNote(notes[0].id);
        await h.services.refreshTimeline();
        await tester.pumpAndSettle();
        expect(
          timeline(tester).model.notes.where((n) => n.pinnedAt != null),
          isEmpty,
        );
        final model = timeline(tester).model;
        await model.selectTags({work.id});
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 45));
        await model.selectTags({home.id});
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 45));
        await model.clearFilters();
        await tester.pumpAndSettle();
        expect(
          model.notes.map((n) => n.id),
          unorderedEquals(notes.map((n) => n.id)),
        );
        for (final note in notes) {
          expect(card(note.id), findsOneWidget);
        }
        await model.selectTags({'missing-tag'});
        await tester.pumpAndSettle();
        expect(find.byType(NoteCard), findsNothing);
        await model.clearFilters();
        await tester.pumpAndSettle();
        expect(find.byType(NoteCard), findsNWidgets(5));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'last deletion reaches the empty state without a jump or duplicate, reduced=$reduced',
      (tester) async {
        final h = await open(tester, reduced: reduced);
        final note = (await h.services.captureText('Last note'))!;
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        await timeline(tester).deleteWithUndo(note);
        await tester.pumpAndSettle();
        expect(card(note.id), findsNothing);
        expect(timeline(tester).model.notes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('updated brief text blends in and old semantics disappear', (
    tester,
  ) async {
    final h = await open(tester);
    await h.preferences.setShowDaySummary(true);
    await h.preferences.setAiEnabled(true);
    await h.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
    );
    Future<void> summary(String text) => h.preferences.setAiDaySummary(
      text: text,
      dateKey: NexPreferences.daySummaryDateKey(DateTime.now()),
      at: DateTime.now(),
      source: 'fixture',
    );
    await summary('The earlier brief');
    await h.services.captureText('A note for the brief');
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.text('The earlier brief'), findsOneWidget);
    await summary('A freshly updated brief');
    await h.services.refreshTimeline();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('A freshly updated brief'), findsOneWidget);
    expect(
      find.text('The earlier brief'),
      findsOneWidget,
      reason: 'the old words are fading out',
    );
    await tester.pumpAndSettle();
    expect(find.text('The earlier brief'), findsNothing);
    expect(find.text('A freshly updated brief'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('glass toggles use the theme reveal in both directions', (
    tester,
  ) async {
    final h = await open(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final before = tester
        .widget<NexThemeReveal>(find.byType(NexThemeReveal))
        .signature;
    Finder overlay() => find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_RevealPainter',
    );
    for (final enabled in [true, false]) {
      await h.preferences.setLiquidGlass(enabled);
      await tester.pump();
      expect(overlay(), findsOneWidget);
      await tester.pumpAndSettle();
      expect(overlay(), findsNothing);
    }
    expect(
      tester.widget<NexThemeReveal>(find.byType(NexThemeReveal)).signature,
      before,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
