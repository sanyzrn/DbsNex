import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_brand.dart';

void main() {
  setUp(() => NexLivingLogotype.enabled = true);
  tearDown(() => NexLivingLogotype.enabled = false);

  Widget app({bool calm = false, Color seed = Colors.green}) => MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: calm),
      child: const Scaffold(body: Center(child: NexLivingLogotype(height: 16))),
    ),
  );

  testWidgets('moves now and then, and is still in between', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    // Still at first: nothing is ticking until the first movement is due.
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pump(NexLivingLogotype.firstDelay);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();

    // And again, an interval later — then still once more.
    await tester.pump(NexLivingLogotype.interval);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // Gone with the screen, timer and all: the test would fail on a timer
    // left pending.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('never moves with animations turned off', (tester) async {
    await tester.pumpWidget(app(calm: true));
    await tester.pump(NexLivingLogotype.firstDelay);
    await tester.pump(NexLivingLogotype.interval);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a touch plays it now and starts the wait again', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.tap(find.byType(NexLivingLogotype));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'played now');
    await tester.pumpAndSettle();

    // The first movement was due at 1.6 s; the touch moved it a whole
    // interval on, so nothing starts where it would have.
    await tester.pump(NexLivingLogotype.firstDelay);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(NexLivingLogotype.interval);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
