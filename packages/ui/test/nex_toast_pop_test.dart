import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  Widget host(Widget child, {bool animations = true}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: !animations),
      child: Scaffold(body: child),
    ),
  );

  Finder scaleOf(Finder ancestor) =>
      find.descendant(of: ancestor, matching: find.byType(ScaleTransition));

  testWidgets('the child is on screen once the pop settles', (tester) async {
    await tester.pumpWidget(host(const NexToastPop(child: Text('saved'))));
    await tester.pumpAndSettle();

    expect(find.text('saved'), findsOneWidget);
    expect(
      tester
          .widget<ScaleTransition>(scaleOf(find.byType(NexToastPop)))
          .scale
          .value,
      1,
    );
  });

  testWidgets('reduced motion skips straight to settled, no animated frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const NexToastPop(child: Text('saved')), animations: false),
    );
    // One frame for the post-frame callback to run, none of the entrance
    // curve's own duration — the same convention CommitReceipt follows for
    // the same accessibility setting.
    await tester.pump();

    expect(
      tester
          .widget<ScaleTransition>(scaleOf(find.byType(NexToastPop)))
          .scale
          .value,
      1,
    );
  });

  testWidgets('dismiss leaves the way it came — a small settle, then gone', (
    tester,
  ) async {
    // A toast that lands with a pop and leaves with nothing reads as
    // half-built. The host says dismiss; the content settles toward 0.92
    // and fades on the exit token, and only then is taken down.
    final controller = NexToastPopController();
    var up = false;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => up
              ? const SizedBox()
              : NexToastPop(
                  controller: controller,
                  onGone: () => setState(() => up = true),
                  child: const Text('saved'),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.isAttached, isTrue);

    controller.dismiss();
    await tester.pump();
    await tester.pump(NexMotion.exit ~/ 2);
    // On the way out: smaller than it stood, dimmer than it was.
    expect(
      tester
          .widget<ScaleTransition>(
            find
                .descendant(
                  of: find.byType(NexToastPop),
                  matching: find.byType(ScaleTransition),
                )
                .first,
          )
          .scale
          .value,
      allOf(greaterThan(0.92), lessThan(1)),
    );
    await tester.pumpAndSettle();

    expect(up, isTrue);
    expect(find.byType(NexToastPop), findsNothing);
    expect(controller.isAttached, isFalse);
  });

  testWidgets('reduced motion dismisses without animated frames', (
    tester,
  ) async {
    final controller = NexToastPopController();
    var gone = 0;
    await tester.pumpWidget(
      host(
        NexToastPop(
          controller: controller,
          onGone: () => gone++,
          child: const Text('saved'),
        ),
        animations: false,
      ),
    );
    await tester.pump();

    controller.dismiss();
    await tester.pump();

    expect(gone, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
