import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('reveal retains child state and settles, reduced=$reduced', (
      tester,
    ) async {
      var visible = true;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Material(
            child: StatefulBuilder(
              builder: (context, setState) {
                change = setState;
                return Align(
                  alignment: Alignment.topCenter,
                  child: NexReveal(
                    visible: visible,
                    maintainState: true,
                    child: const SizedBox(
                      width: 200,
                      height: 120,
                      child: TextField(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final state = tester.state(find.byType(TextField));
      change(() => visible = false);
      await tester.pump();
      if (!reduced) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.getSize(find.byType(NexReveal)).height,
          inExclusiveRange(0, 120),
        );
      }
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(NexReveal)).height, 0);
      expect(find.byType(TextField), findsNothing);
      change(() => visible = true);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(state));
      expect(tester.getSize(find.byType(NexReveal)).height, 120);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
  testWidgets('changing reduced motion keeps async content state', (
    tester,
  ) async {
    var reduced = false;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: const NexAnimatedSize(
                  child: SizedBox(width: 200, height: 120, child: TextField()),
                ),
              );
            },
          ),
        ),
      ),
    );
    final state = tester.state(find.byType(TextField));
    for (final value in [true, false, true]) {
      change(() => reduced = value);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(state));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
  });
}
