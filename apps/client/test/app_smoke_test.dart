import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app.dart';

void main() {
  testWidgets('Phase 0: the app boots and renders an empty screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const NexApp());

    // An empty app: a single Scaffold with no product UI in it.
    expect(find.byType(NexApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });
}
