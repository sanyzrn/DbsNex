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
}
