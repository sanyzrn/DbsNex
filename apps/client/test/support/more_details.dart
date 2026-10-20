import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens a form's "more details" button (a `NexMoreDetails`) when it is
/// still closed; a correction of a saved item opens with them already.
Future<void> openMoreDetails(WidgetTester tester, String key) async {
  final toggle = find.byKey(ValueKey(key));
  if (toggle.evaluate().isEmpty) return;
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}
