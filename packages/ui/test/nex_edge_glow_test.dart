import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// The assistant's light: the bloom while + is held, and the thin border that
/// turns round the screen for as long as the assistant is open.
void main() {
  Future<void> show(WidgetTester tester, {bool still = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: still),
            child: const Scaffold(
              body: NexAmbientEdgeGlow(
                colors: nexAssistantSpectrum,
                child: Text('assistant'),
              ),
            ),
          ),
        ),
      );

  Finder border() => find.byWidgetPredicate(
    (w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == '_AmbientBorderPainter',
  );

  testWidgets('the border turns while the assistant is open', (tester) async {
    await show(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(border(), findsOneWidget);
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'a turning border keeps asking for frames',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with reduced motion the border stays, still', (tester) async {
    await show(tester, still: true);
    await tester.pump();
    expect(border(), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
