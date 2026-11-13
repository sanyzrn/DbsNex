import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_brand.dart';

/// The wordmark moves when it is touched, and only then (2.6.26).
void main() {
  Widget app({bool calm = false}) => MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
    ),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: calm),
      child: const Scaffold(body: Center(child: NexLivingLogotype(height: 16))),
    ),
  );

  testWidgets('left alone, it never moves', (tester) async {
    await tester.pumpWidget(app());
    // A minute on the home screen: no frame is asked for, ever. It used to
    // move every seven seconds.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'second $i');
    }
  });

  testWidgets('a touch plays it once', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(NexLivingLogotype));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'played now');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'and not again');
  });

  testWidgets('never moves with animations turned off', (tester) async {
    await tester.pumpWidget(app(calm: true));
    await tester.tap(find.byType(NexLivingLogotype));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('moves on a layer of its own', (tester) async {
    await tester.pumpWidget(app());
    expect(
      find.descendant(
        of: find.byType(NexLivingLogotype),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );
  });
}
