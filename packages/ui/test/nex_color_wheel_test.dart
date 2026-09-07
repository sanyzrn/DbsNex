import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// The disc has three descriptions of the same fact — where a hue sits — and
/// the bug worth testing for is them disagreeing.
///
/// It shipped disagreeing: the sweep carried `startAngle: -pi/2` *and* a
/// `GradientRotation(-pi/2)`, so the paint was a quarter turn from the
/// arithmetic. The thumb sat on green and the picker returned orange. Nothing
/// caught it, because every existing test asked the widget what it thought
/// rather than looking at what it drew.
///
/// So this one reads pixels.
void main() {
  const diameter = 200.0;

  const discKey = ValueKey('disc');

  Widget host(double hue, double saturation) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: discKey,
          child: NexColorWheel(
            hue: hue,
            saturation: saturation,
            value: 1,
            diameter: diameter,
            onChanged: (_, _) {},
          ),
        ),
      ),
    ),
  );

  /// The hue actually painted at [degrees] clockwise from the top, sampled
  /// from the rendered disc.
  Future<double> paintedHueAt(WidgetTester tester, double degrees) async {
    // The disc and nothing else, so the pixel arithmetic below is in the
    // wheel's own coordinates. `toImage` renders at pixelRatio 1, so the
    // image is `diameter` across whatever the test view's density is.
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(discKey),
    );
    late double hue;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = Uint8List.view(data!.buffer);
      final radius = diameter / 2;
      // Well outside the white centre and inside the rim, so the sample is
      // the hue and not the saturation ramp or an antialiased edge.
      final radians = (degrees - 90) * math.pi / 180;
      final x = (radius + math.cos(radians) * radius * 0.8).round();
      final y = (radius + math.sin(radians) * radius * 0.8).round();
      final offset = (y * image.width + x) * 4;
      final colour = HSVColor.fromColor(
        Color.fromARGB(
          255,
          pixels[offset],
          pixels[offset + 1],
          pixels[offset + 2],
        ),
      );
      hue = colour.hue;
      image.dispose();
    });
    return hue;
  }

  double gapBetween(double a, double b) {
    final raw = (a - b).abs() % 360;
    return raw > 180 ? 360 - raw : raw;
  }

  testWidgets('the disc paints the hue its own arithmetic puts there', (
    tester,
  ) async {
    await tester.pumpWidget(host(0, 1));
    await tester.pumpAndSettle();

    // Red at the top, then clockwise through the spectrum. Before the fix the
    // top painted hue 90 and this failed by the exact quarter turn.
    for (final expected in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]) {
      final painted = await paintedHueAt(tester, expected);
      expect(
        gapBetween(painted, expected),
        lessThan(12),
        reason: 'at $expected° from the top the disc painted hue $painted',
      );
    }
  });

  test('reading a touch is the exact inverse of placing the thumb', () {
    // Cheap, and it holds the two halves together at every angle rather than
    // the handful the widget tests can afford to render.
    for (var hue = 0.0; hue < 360; hue += 3) {
      final offset = NexColorWheel.offsetForHue(hue, 1, 100);
      expect(
        gapBetween(NexColorWheel.hueForOffset(offset), hue),
        lessThan(0.001),
        reason: 'hue $hue did not survive the round trip',
      );
    }
  });

  testWidgets('a tap picks the colour under the finger', (tester) async {
    double? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: NexColorWheel(
              hue: 0,
              saturation: 1,
              value: 1,
              diameter: diameter,
              onChanged: (hue, _) => picked = hue,
            ),
          ),
        ),
      ),
    );

    final centre = tester.getCenter(find.byType(NexColorWheel));
    for (final (degrees, expected) in [
      (0.0, 0.0),
      (90.0, 90.0),
      (180.0, 180.0),
      (270.0, 270.0),
    ]) {
      final radians = (degrees - 90) * math.pi / 180;
      await tester.tapAt(
        centre +
            Offset(math.cos(radians), math.sin(radians)) * (diameter / 2 * 0.8),
      );
      await tester.pump();
      expect(gapBetween(picked!, expected), lessThan(1), reason: '$degrees°');
    }
  });
}
