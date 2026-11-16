import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/home_layout_sheet.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/nex_brand.dart';
import 'package:nex_client/widgets/search_field_header.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// The home screen as it is since 2.8.0: one header for the day — the date,
/// the greeting, the smart summary, the pinned tools — the search field in
/// the app bar, and the notes under a row that says what narrows them and
/// how they are laid out.
void main() {
  late NexTestHarness h;

  setUp(() async {
    h = await NexTestHarness.create(name: 'nex_home_today_');
  });
  tearDown(() => h.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
  }

  testWidgets('a line the app wrote from a note opens that note', (
    tester,
  ) async {
    // The report style writes its own lines and needs no provider.
    await h.preferences.setBriefStyle(NexBriefStyle.report);
    final note = (await h.services.captureText('renew the passport'))!;
    await h.services.setDueAt(
      note.id,
      DateTime.now().add(const Duration(hours: 5)),
    );
    await h.services.captureText('an ordinary thought');
    await open(tester);

    final recap = find.byKey(const ValueKey('timeline-recap'));
    expect(recap, findsOneWidget);
    final line = find.descendant(
      of: recap,
      matching: find.textContaining('renew the passport'),
    );
    expect(line, findsOneWidget);
    // It says it leads somewhere, at its end.
    expect(
      find.descendant(
        of: recap,
        matching: find.byIcon(Icons.navigate_next_rounded),
      ),
      findsWidgets,
    );
    expect(find.byType(NoteDetailSheet), findsNothing);

    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(find.byType(NoteDetailSheet), findsOneWidget);
    expect(
      tester.widget<NoteDetailSheet>(find.byType(NoteDetailSheet)).noteId,
      note.id,
    );
    // Opening a line is not a fold: the card is as open as it was.
    expect(h.preferences.daySummaryFolded, isFalse);
  });

  testWidgets('the brief stands between the greeting and the notes', (
    tester,
  ) async {
    await h.preferences.setBriefStyle(NexBriefStyle.report);
    await h.preferences.setDisplayName('Saeed');
    await h.preferences.togglePinnedTool('generator');
    final note = (await h.services.captureText('a tagged note'))!;
    await h.services.addTag(noteId: note.id, name: 'work');
    await open(tester);

    double top(Finder finder) => tester.getRect(finder).top;
    final greeting = find.textContaining('Saeed');
    final recap = find.byKey(const ValueKey('timeline-recap'));
    final tools = find.byKey(const ValueKey('pinned-tool-generator'));
    final tags = find.byType(TagFilterRow);
    final card = find.byType(NoteCard);
    expect(greeting, findsOneWidget);
    // One header for the day, then where the notes begin.
    expect(top(greeting), lessThan(top(recap)));
    expect(top(recap), lessThan(top(tools)));
    expect(top(tools), lessThan(top(tags)));
    expect(top(tags), lessThan(top(card)));
  });

  testWidgets('the wordmark gives the bar to the field while searching', (
    tester,
  ) async {
    await h.services.captureText('a note about rockets');
    await open(tester);

    final bar = find.byType(AppBar);
    final mark = find.descendant(
      of: bar,
      matching: find.byType(NexLivingLogotype),
    );
    final pill = find.byType(NexSearchPill);
    expect(mark, findsOneWidget);
    final resting = tester.getSize(pill).width;

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(mark, findsNothing);
    expect(tester.getSize(pill).width, greaterThan(resting + 60));
    // The layout button is the home screen's, not a search's.
    expect(find.byIcon(Icons.dashboard_customize_outlined), findsNothing);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(mark, findsOneWidget);
    expect(tester.getSize(pill).width, closeTo(resting, 0.5));
    expect(find.byIcon(Icons.dashboard_customize_outlined), findsOneWidget);
  });

  testWidgets('the home layout sheet pins a tool and takes it off again', (
    tester,
  ) async {
    await h.services.captureText('a note');
    await open(tester);
    expect(find.byKey(const ValueKey('pinned-tool-generator')), findsNothing);

    await tester.tap(find.byIcon(Icons.dashboard_customize_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(HomeLayoutSheet), findsOneWidget);
    final chip = find.byKey(const ValueKey('layout-pin-generator'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(h.preferences.pinnedTools, ['generator']);
    // On the home screen behind the sheet at once.
    expect(
      find.byKey(const ValueKey('pinned-tool-generator'), skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(h.preferences.pinnedTools, isEmpty);
  });

  testWidgets('the day chip waits for the row to be held at the top, and '
      'does not repeat a heading on screen', (tester) async {
    for (var i = 0; i < 30; i++) {
      await h.services.captureText('note number $i');
    }
    await h.preferences.setBriefStyle(NexBriefStyle.report);
    await h.preferences.setDisplayName('Saeed');
    await h.services.refreshTimeline();
    await open(tester);

    String? chip() {
      final text = find.descendant(
        of: find.byType(TimelineStickyDay),
        matching: find.byType(Text),
      );
      return text.evaluate().isEmpty
          ? null
          : tester.widget<Text>(text.last).data;
    }

    final list = find.byType(CustomScrollView);
    final header = find.text('Today');
    expect(header, findsOneWidget);
    expect(chip(), isNull);

    // Past where the chip used to appear (160), with the day's header still
    // on its way up and the heading in full view: nothing to add.
    final lead = tester.getRect(header).top - tester.getRect(list).top;
    expect(lead, greaterThan(170), reason: 'the header is taller than 160');
    await tester.drag(list, Offset(0, -(lead - 60)));
    await tester.pumpAndSettle();
    expect(header, findsOneWidget);
    expect(chip(), isNull, reason: 'the heading on screen already says it');

    // Well into the day, its heading gone: now the chip names it.
    await tester.drag(list, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(chip(), 'Today');
    // The one "Today" left on screen is the chip's own.
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: find.byType(TimelineStickyDay), matching: header),
      findsOneWidget,
    );
  });
}
