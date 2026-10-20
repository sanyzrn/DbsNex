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
