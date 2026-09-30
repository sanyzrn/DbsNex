import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  Widget app(Object signature, Color color, {bool reduceMotion = false}) =>
      MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: reduceMotion,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: NexThemeReveal(
            signature: signature,
            child: ColoredBox(color: color, child: const SizedBox.expand()),
          ),
        ),
      );

  Finder overlay() => find.descendant(
    of: find.byType(NexThemeReveal),
    matching: find.byType(CustomPaint),
  );

  testWidgets('a new look opens over the old one, then the old one goes', (
    tester,
  ) async {
    await tester.pumpWidget(app('light', Colors.white));
    expect(overlay(), findsNothing);

    await tester.tapAt(const Offset(40, 700));
    await tester.pumpWidget(app('dark', Colors.black));
    expect(overlay(), findsOneWidget, reason: 'the old theme, being opened');

    await tester.pump(const Duration(milliseconds: 300));
    expect(overlay(), findsOneWidget);
    await tester.pumpAndSettle();
    expect(overlay(), findsNothing, reason: 'nothing left over the app');
  });

  testWidgets('the same look again changes nothing', (tester) async {
    await tester.pumpWidget(app('light', Colors.white));
    await tester.pumpWidget(app('light', Colors.white));
    expect(overlay(), findsNothing);
  });

  testWidgets('with animations off the theme just changes', (tester) async {
    await tester.pumpWidget(app('light', Colors.white, reduceMotion: true));
    await tester.pumpWidget(app('dark', Colors.black, reduceMotion: true));
    expect(overlay(), findsNothing);
  });
}
