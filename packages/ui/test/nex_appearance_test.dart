import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  test('background patterns keep stable wire names', () {
    for (final pattern in NexBackgroundPattern.values) {
      expect(NexBackgroundPatternWire.fromWire(pattern.wireName), pattern);
    }
    expect(
      NexBackgroundPatternWire.fromWire('future-pattern'),
      NexBackgroundPattern.plain,
    );
  });

  test('liquid glass theme remains independent of brightness', () {
    for (final theme in [
      nexLightTheme(liquidGlass: true),
      nexDarkTheme(liquidGlass: true),
    ]) {
      expect(theme.extension<NexVisualStyle>()!.liquidGlass, isTrue);
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
      expect(theme.bottomSheetTheme.backgroundColor, Colors.transparent);
    }
  });

  testWidgets('glass surface uses real blur and respects high contrast', (
    tester,
  ) async {
    Future<void> pump({required bool highContrast}) => tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(liquidGlass: true),
        home: MediaQuery(
          data: MediaQueryData(highContrast: highContrast),
          child: const Scaffold(body: NexGlassSurface(child: Text('Glass'))),
        ),
      ),
    );

    await pump(highContrast: false);
    expect(find.byType(BackdropFilter), findsOneWidget);

    await pump(highContrast: true);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Glass'), findsOneWidget);
  });

  testWidgets('every background preset paints behind its child', (
    tester,
  ) async {
    for (final pattern in NexBackgroundPattern.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          home: NexAppBackground(
            pattern: pattern,
            child: const Text('Content'),
          ),
        ),
      );
      expect(find.text('Content'), findsOneWidget);
      if (pattern != NexBackgroundPattern.plain) {
        expect(find.byType(CustomPaint), findsWidgets);
      }
    }
  });
}
