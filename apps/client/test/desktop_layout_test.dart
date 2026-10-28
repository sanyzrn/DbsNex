import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/desktop/desktop_note_card.dart';
import 'package:nex_client/modules/module_rollout.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/capture_sheet.dart';

import 'support/nex_harness.dart';

/// docs/27-desktop.md, phase 1 and 2: on a desktop, from 1000 wide, the app
/// has a left rail and a grid; below that, and on every phone and tablet,
/// it is the phone's, untouched.
void main() {
  Future<NexTestHarness> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    final a = (await h.services.captureText('Plan\n\nOne\nTwo'))!;
    await h.services.addTag(noteId: a.id, name: 'work', color: '#2F6FDE');
    await h.services.captureText('A single thought');
    await tester.pumpWidget(h.app());
    // The rail reads the tags from the database, which answers in real time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    return h;
  }

  // The desktop layout is for desktop platforms. The override is reset inside
  // the body: the framework checks it before tearDown runs.
  Future<void> onDesktop(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('a wide window has the rail and a grid of cards', (tester) async {
    await onDesktop(tester, () async {
      await open(tester, const Size(1280, 800));
      expect(find.byType(FloatingActionButton), findsNothing);
      for (final label in [
        'Capture',
        'Notes',
        'Recurring',
        'Library',
        'Tools',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      // The tag is in the rail, with its count.
      expect(find.text('Work'), findsWidgets);
      expect(find.byType(NexDesktopNoteCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the rail goes to a section and back, and a sheet is a panel', (
    tester,
  ) async {
    await onDesktop(tester, () async {
      await open(tester, const Size(1280, 800));
      await tester.tap(find.text('Library').first);
      // Fixed pumps: the library's storage panel spins until its read returns.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Trash'), findsOneWidget);
      // The page keeps to a reading width, beside the rail.
      final page = tester.getRect(find.text('Trash'));
      expect(page.left, greaterThan(232));

      await tester.tap(find.text('Notes').first);
      await tester.pumpAndSettle();
      expect(find.byType(NexDesktopNoteCard), findsNWidgets(2));

      await tester.tap(find.text('Capture').first);
      await tester.pumpAndSettle();
      final panel = tester.getSize(find.byType(CaptureSheet));
      expect(panel.width, lessThanOrEqualTo(560));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a tablet in landscape keeps the phone layout', (tester) async {
    // Android at 1280 wide: no rail, no grid — the dock and rows as before.
    await open(tester, const Size(1280, 800));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(NexDesktopNoteCard), findsNothing);
    expect(find.text('Recurring'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone-sized window has the dock and rows, as before', (
    tester,
  ) async {
    await open(tester, const Size(400, 800));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(NexDesktopNoteCard), findsNothing);
    expect(find.text('Recurring'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cycle is not offered on a desktop, and a restored one is off', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = await pumpNexApp(tester);
      await h.preferences.setCycleEnabled(true);
      expect(h.preferences.cycleEnabled, isFalse);
      expect(nexModuleAvailable('cycle'), isFalse);
      await tester.tap(find.text('Tools').first);
      await tester.pumpAndSettle();
      expect(find.text('Cycle'), findsNothing);
      expect(find.text('Modules'), findsNothing);
      expect(find.text('Add modules'), findsNothing);
      expect(find.text('Password generator'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone Cycle is still there', (tester) async {
    expect(nexModuleAvailable('cycle'), isTrue);
    final h = await pumpNexApp(tester);
    await h.preferences.setCycleEnabled(true);
    expect(h.preferences.cycleEnabled, isTrue);
  });
}
