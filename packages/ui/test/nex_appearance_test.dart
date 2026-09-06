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

  test('liquid glass leaves the page transparent and a sheet opaque', () {
    for (final theme in [
      nexLightTheme(liquidGlass: true),
      nexDarkTheme(liquidGlass: true),
    ]) {
      expect(theme.extension<NexVisualStyle>()!.liquidGlass, isTrue);
      // The page is transparent on purpose: the background is painted once at
      // the root, and every screen sits on it.
      expect(theme.scaffoldBackgroundColor, Colors.transparent);

      // A sheet is not, and this assertion used to say it was. Transparency
      // here is only correct if every sheet wraps itself in a glass panel, and
      // most do not — the reminder picker and the chat history are plain
      // sheets, so they were drawn with no surface at all and put their text
      // straight onto the timeline. A sheet covers the page rather than
      // sitting in it; seeing through one is not depth.
      for (final sheet in [
        theme.bottomSheetTheme.backgroundColor!,
        theme.bottomSheetTheme.modalBackgroundColor!,
      ]) {
        expect(sheet.a, greaterThan(0.9));
      }
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

  test('the preset list only ever grows', () {
    // Wire names are stored, so a rename or a reorder that changes one turns
    // every device already carrying it back to Plain on the next launch.
    // These are the ones that have shipped.
    expect(
      NexBackgroundPattern.values.map((p) => p.wireName),
      containsAll(<String>['plain', 'aurora', 'ripple', 'weave']),
    );
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

  testWidgets('every background preset paints in both themes', (tester) async {
    // A preset is a picture drawn with alpha over whatever ground the theme
    // gives it, so one tuned only against white disappears — or shouts — on
    // black. Painting is exercised here rather than only built: a bad shader
    // or a malformed path throws inside `paint`, which a widget that is never
    // rasterised will never reach.
    for (final theme in [nexLightTheme(), nexDarkTheme()]) {
      for (final pattern in NexBackgroundPattern.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              child: NexAppBackground(
                pattern: pattern,
                child: const Text('Content'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${pattern.wireName} threw while painting',
        );
      }
    }
  });
}
