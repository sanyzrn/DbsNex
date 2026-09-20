import 'dart:math' as math;

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

  test('glass keeps body text legible over any backdrop it can land on', () {
    // What this guards is the numbers, not the painter: it runs the theme's
    // own films through a reference compositor that follows the same four
    // steps `_GlassWashPainter` draws. Change a film in `nex_tokens.dart` and
    // this fails; change how the painter stacks them and it will not.
    //
    // The list below is every kind of thing that can end up behind a glass
    // panel, including the two nobody plans for: a note the user has coloured
    // near-black, and one coloured near-white.
    const backdrops = <Color>[
      Color(0xFF000000),
      Color(0xFF131312), // the dark page
      Color(0xFF1E1E1E), // a dark card
      Color(0xFF808080),
      Color(0xFF0084F7), // the accent
      Color(0xFFFF383C), // danger
      Color(0xFFF5F6F6), // the light page
      Color(0xFFEFE7D8), // the comfort page
      Color(0xFFFFFFFF),
    ];

    for (final (theme, floor) in [
      (nexLightTheme(liquidGlass: true), 4.9),
      (nexLightTheme(liquidGlass: true, comfortMode: true), 4.6),
      (nexDarkTheme(liquidGlass: true), 4.5),
      (nexDarkTheme(liquidGlass: true, comfortMode: true), 4.5),
    ]) {
      final wash = theme.extension<NexVisualStyle>()!.glassWash;
      final ink = theme.colorScheme.onSurface;
      for (final backdrop in backdrops) {
        final glass = _compose(wash, backdrop);
        expect(
          _contrast(ink, glass),
          greaterThanOrEqualTo(floor),
          reason:
              'ink $ink on glass over $backdrop came out $glass, which is '
              '${_contrast(ink, glass).toStringAsFixed(2)}:1',
        );
      }
    }
  });

  test('the glass edge is four shadows and none of them is a slab', () {
    for (final theme in [
      nexLightTheme(liquidGlass: true),
      nexDarkTheme(liquidGlass: true),
    ]) {
      final visual = theme.extension<NexVisualStyle>()!;
      final edge = visual.glassEdge;
      expect(edge, hasLength(4));
      // The two rim slivers are offset in opposite directions and pulled back
      // far enough that nothing shows at the top or bottom. Without the
      // negative spread they are a drop shadow on each side.
      expect(edge[1].offset.dx, -edge[2].offset.dx);
      for (final rim in [edge[1], edge[2]]) {
        expect(rim.spreadRadius, lessThan(0));
        expect(rim.spreadRadius.abs(), lessThan(rim.offset.dx.abs()));
        expect(rim.blurRadius, 0);
      }
      // A card's shadow is what this used to be. Anything this side of a few
      // percent is back to reading as a card that happens to be blurred.
      expect(visual.glassShadow.a, lessThan(0.1));
    }
  });
}

/// The four films of [NexGlassWash], composited the way the painter draws
/// them: two source-over, one additive, one luminosity.
Color _compose(NexGlassWash wash, Color backdrop) {
  var out = backdrop;
  for (final film in wash.films) {
    out = Color.alphaBlend(film, out);
  }
  out = Color.from(
    alpha: 1,
    red: _unit(out.r + wash.lift.r * wash.lift.a),
    green: _unit(out.g + wash.lift.g * wash.lift.a),
    blue: _unit(out.b + wash.lift.b * wash.lift.a),
  );
  return _luminosityOver(wash.anchor, out);
}

/// CSS's `luminosity` blend: the backdrop keeps its hue, the source supplies
/// the brightness, and the result is composited at the source's alpha.
Color _luminosityOver(Color source, Color backdrop) {
  double lum(double r, double g, double b) => 0.3 * r + 0.59 * g + 0.11 * b;
  final delta =
      lum(source.r, source.g, source.b) -
      lum(backdrop.r, backdrop.g, backdrop.b);
  var r = backdrop.r + delta;
  var g = backdrop.g + delta;
  var b = backdrop.b + delta;
  // ClipColor: pull anything that left the cube back toward its own luma.
  final l = lum(r, g, b);
  final low = math.min(r, math.min(g, b));
  final high = math.max(r, math.max(g, b));
  if (low < 0 && l != low) {
    r = l + (r - l) * l / (l - low);
    g = l + (g - l) * l / (l - low);
    b = l + (b - l) * l / (l - low);
  }
  if (high > 1 && high != l) {
    r = l + (r - l) * (1 - l) / (high - l);
    g = l + (g - l) * (1 - l) / (high - l);
    b = l + (b - l) * (1 - l) / (high - l);
  }
  final a = source.a;
  return Color.from(
    alpha: 1,
    red: _unit(r * a + backdrop.r * (1 - a)),
    green: _unit(g * a + backdrop.g * (1 - a)),
    blue: _unit(b * a + backdrop.b * (1 - a)),
  );
}

/// ClipColor and the additive step can both land a hair outside the cube on
/// float error, and `Color.from` is not the place to find that out.
double _unit(double v) => v.clamp(0.0, 1.0);

double _contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}
