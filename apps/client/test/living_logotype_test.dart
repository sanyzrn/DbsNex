import 'dart:async';

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

  testWidgets('waits while something else on screen is moving', (tester) async {
    final other = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 3),
    );
    addTearDown(other.dispose);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 100));
    // A list in flight, say: something keeps asking for frames.
    unawaited(other.forward());
    await tester.pump(NexLivingLogotype.firstDelay);
    final logotype = find.byType(NexLivingLogotype);
    double moved() => tester
        .widget<CustomPaint>(
          find.descendant(of: logotype, matching: find.byType(CustomPaint)),
        )
        .painter
        .hashCode
        .toDouble();
    final before = moved();
    await tester.pump(const Duration(milliseconds: 300));
    expect(moved(), before, reason: 'held while the other animation runs');
    other.stop();
    await tester.pumpAndSettle();
    // Once it is quiet, the movement it owed starts within a retry.
    await tester.pump(NexLivingLogotype.busyRetry);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
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
    await tester.pumpWidget(const SizedBox());
  });
}
