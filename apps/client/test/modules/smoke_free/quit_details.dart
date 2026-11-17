import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A new habit's setup shows what it is and when it starts; the amounts,
/// price, goal and reason sit behind one button. Opens them when they are
/// still closed (a correction opens with everything).
Future<void> openQuitDetails(WidgetTester tester) async {
  final toggle = find.byKey(const ValueKey('quit-details-toggle'));
  if (toggle.evaluate().isEmpty) return;
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

/// Reveals a lazy row in either direction without changing its assertions.
Future<void> revealQuit(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).last;
  for (final delta in [300.0, -300.0]) {
    for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
      final position = tester.state<ScrollableState>(scrollable).position;
      final before = position.pixels;
      await tester.drag(scrollable, Offset(0, -delta));
      await tester.pumpAndSettle();
      if (position.pixels == before) break;
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
