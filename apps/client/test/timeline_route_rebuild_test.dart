import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// Opening a note — or anything else — over the timeline must not rebuild the
/// timeline underneath.
///
/// It did: the screen asked `ModalRoute.of(context)` for its route, which made
/// it depend on whether anything covered it, so every card was rebuilt as a
/// note rose over it and again as it fell away — about two thousand widgets
/// each way, on the frames the animation needed most.
void main() {
  testWidgets('the cards are left alone as a note opens and closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    for (var i = 0; i < 8; i++) {
      await h.services.captureText('Note $i\n\nA line of body for note $i');
    }
    await tester.pumpWidget(h.app());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final rebuilt = <Type, int>{};
    debugOnRebuildDirtyWidget = (element, _) {
      final type = element.widget.runtimeType;
      rebuilt[type] = (rebuilt[type] ?? 0) + 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    await tester.tap(find.byType(NoteCard).first);
    await tester.pumpAndSettle();
    expect(rebuilt[TimelineScreen], isNull, reason: 'opening');
    expect(rebuilt[NoteCard], isNull, reason: 'opening');

    rebuilt.clear();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(rebuilt[TimelineScreen], isNull, reason: 'closing');
    expect(rebuilt[NoteCard], isNull, reason: 'closing');

    debugOnRebuildDirtyWidget = null;
    await tester.pumpWidget(const SizedBox());
  });
}
