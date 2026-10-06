import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_banner.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// W7.5: picking several notes from a card's hold menu, and doing one thing
/// to all of them from the bar that takes the dock's place.
void main() {
  late NexTestHarness harness;
  late List<String> clipboard;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_bulk_select_');
    for (final text in ['alpha note', 'beta note', 'gamma note']) {
      await harness.services.captureText(text);
    }
    await harness.services.refreshTimeline();
    clipboard = [];
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester, {double width = 1080 / 2.75}) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = Size(width * 2.75, 2340);
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
  }

  Finder card(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(NoteCard));

  bool? selectedOf(WidgetTester tester, String text) =>
      tester.widget<NoteCard>(card(text)).selected;

  Future<void> select(WidgetTester tester, String text) async {
    await tester.longPress(card(text));
    await tester.pumpAndSettle();
    final entry = find.text('Select');
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  Finder bar() => find.byKey(const ValueKey('selection-bar'));
  Finder count(String text) => find.descendant(
    of: find.byKey(const ValueKey('selection-count')),
    matching: find.text(text),
  );

  testWidgets('the dock turns into the selection bar, not a cut', (
    tester,
  ) async {
    await open(tester);
    final dock = find.byType(NexNavigationDock);
    expect(dock, findsOneWidget);

    await tester.longPress(card('alpha note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    // Partway through: the two bars are both on screen, the arriving one
    // still narrower than it will be.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(dock, findsOneWidget);
    expect(bar(), findsOneWidget);
    final partway = tester.getRect(bar()).width;
    final buttons = find.descendant(
      of: bar(),
      matching: find.byType(IconButton),
    );
    final early = tester.widget<FadeTransition>(
      find
          .ancestor(of: buttons.last, matching: find.byType(FadeTransition))
          .first,
    );
    expect(early.opacity.value, lessThan(1), reason: 'buttons land after');

    await tester.pumpAndSettle();
    expect(dock, findsNothing);
    final settled = tester.getRect(bar()).width;
    expect(partway, lessThan(settled));
    for (final button in buttons.evaluate()) {
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byWidget(button.widget),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
    }
  });

  testWidgets('with reduced motion the bars swap at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await open(tester);
    final swap = tester.widget<AnimatedSwitcher>(
      find
          .ancestor(
            of: find.byType(NexNavigationDock),
            matching: find.byType(AnimatedSwitcher),
          )
          .first,
    );
    expect(swap.duration, Duration.zero);
    expect(swap.reverseDuration, Duration.zero);
  });

  testWidgets('the bar keeps every button whole on a narrow phone', (
    tester,
  ) async {
    // UX-02: at 360dp (and narrower) the margins used to leave less room
    // than the buttons need, and the last one hung past the capsule.
    await open(tester, width: 320);
    await select(tester, 'alpha note');
    expect(tester.takeException(), isNull);
    final buttons = find.descendant(
      of: bar(),
      matching: find.byType(IconButton),
    );
    final barRect = tester.getRect(bar());
    expect(barRect.width, greaterThanOrEqualTo(6 * nexMinTapTarget));
    for (final button in buttons.evaluate()) {
      final rect = tester.getRect(find.byWidget(button.widget));
      expect(rect.width, greaterThanOrEqualTo(nexMinTapTarget));
      expect(barRect.left - 0.5, lessThanOrEqualTo(rect.left));
      expect(rect.right, lessThanOrEqualTo(barRect.right + 0.5));
    }
  });

  testWidgets('Select from the hold menu; taps pick; none left ends it', (
    tester,
  ) async {
    await open(tester);
    expect(bar(), findsNothing);
    expect(selectedOf(tester, 'alpha note'), isNull);

    await select(tester, 'alpha note');
    expect(bar(), findsOneWidget);
    expect(
      find.byTooltip('Capture'),
      findsNothing,
      reason: 'the dock gives way',
    );
    expect(count('1 selected'), findsOneWidget);
    expect(selectedOf(tester, 'alpha note'), isTrue);
    expect(selectedOf(tester, 'beta note'), isFalse);

    // A tap picks instead of opening.
    await tester.tap(card('beta note'));
    await tester.pumpAndSettle();
    expect(count('2 selected'), findsOneWidget);
    expect(find.text('Edit'), findsNothing, reason: 'no note opened');

    await tester.tap(card('beta note'));
    await tester.pumpAndSettle();
    expect(count('1 selected'), findsOneWidget);
    await tester.tap(card('alpha note'));
    await tester.pumpAndSettle();
    expect(bar(), findsNothing, reason: 'the last one put back ends it');
    expect(find.byTooltip('Capture'), findsOneWidget);
    expect(selectedOf(tester, 'alpha note'), isNull);
  });

  testWidgets('close and Back both end it', (tester) async {
    await open(tester);
    await select(tester, 'alpha note');
    await tester.tap(find.byTooltip('Stop selecting'));
    await tester.pumpAndSettle();
    expect(bar(), findsNothing);

    await select(tester, 'alpha note');
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(bar(), findsNothing);
    expect(find.text('alpha note'), findsOneWidget, reason: 'still home');
  });

  testWidgets('copy puts every picked note on the clipboard', (tester) async {
    await open(tester);
    await select(tester, 'alpha note');
    await tester.tap(card('gamma note'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: bar(), matching: find.byTooltip('Copy')),
    );
    await tester.pumpAndSettle();
    expect(clipboard.single, 'alpha note\n\ngamma note');
    expect(bar(), findsNothing);
    nexHideBanner();
    await tester.pumpAndSettle();
  });

  testWidgets('pin pins them all, and again unpins them all', (tester) async {
    await open(tester);
    await select(tester, 'alpha note');
    await tester.tap(card('beta note'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: bar(), matching: find.byTooltip('Pin')),
    );
    await tester.pumpAndSettle();
    var notes = await harness.services.timeline();
    expect(
      notes.where((n) => n.pinnedAt != null).map((n) => n.content).toSet(),
      {'alpha note', 'beta note'},
    );
    nexHideBanner();
    await tester.pumpAndSettle();

    await select(tester, 'alpha note');
    await tester.tap(card('beta note'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: bar(), matching: find.byTooltip('Unpin')),
    );
    await tester.pumpAndSettle();
    notes = await harness.services.timeline();
    expect(notes.where((n) => n.pinnedAt != null), isEmpty);
    nexHideBanner();
    await tester.pumpAndSettle();
  });

  testWidgets('delete takes them all, and one Undo brings them all back', (
    tester,
  ) async {
    await open(tester);
    await select(tester, 'alpha note');
    await tester.tap(card('beta note'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: bar(), matching: find.byTooltip('Delete')),
    );
    await tester.pumpAndSettle();
    expect(find.text('alpha note'), findsNothing);
    expect(find.text('beta note'), findsNothing);
    expect(find.text('gamma note'), findsOneWidget);
    expect(find.text('2 notes deleted'), findsOneWidget);
    expect(bar(), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('alpha note'), findsOneWidget);
    expect(find.text('beta note'), findsOneWidget);
    nexHideBanner();
    await tester.pumpAndSettle();
  });

  testWidgets('a tag goes on every picked note', (tester) async {
    await harness.services.addTag(
      noteId: (await harness.services.timeline()).last.id,
      name: 'work',
    );
    await harness.services.refreshTimeline();
    await open(tester);
    await select(tester, 'beta note');
    await tester.tap(card('gamma note'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: bar(), matching: find.byTooltip('Add tag')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    final notes = await harness.services.timeline();
    for (final text in ['beta note', 'gamma note']) {
      final note = notes.firstWhere((n) => n.content == text);
      expect(
        note.tags.map((t) => t.name.toLowerCase()),
        contains('work'),
        reason: text,
      );
    }
    nexHideBanner();
    await tester.pumpAndSettle();
  });
}
