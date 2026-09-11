import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// RenderRepaintBoundary is not one of the render objects widgets.dart
// re-exports, and reading pixels is how you check that an icon is an icon.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// A painted icon has no glyph to look up and no font to blame, so the two
/// things worth holding are that it obeys the [IconTheme] it is dropped into
/// — it sits in rows of real [Icon]s and is never told its size or colour —
/// and that it actually draws something at the size those rows use.
void main() {
  const boundaryKey = ValueKey('icon');

  Widget host({double? size, Color? color, IconThemeData? theme}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: IconTheme(
              data: theme ?? const IconThemeData(size: 48, color: Colors.black),
              child: NexSummariseIcon(size: size, color: color),
            ),
          ),
        ),
      ),
    ),
  );

  /// How many pixels of the rendered icon are not the white behind it.
  Future<int> inkedPixels(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    var inked = 0;
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage();
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final Uint8List pixels = data!.buffer.asUint8List();
      for (var i = 0; i < pixels.length; i += 4) {
        // Anything meaningfully darker than the ground. Antialiasing puts a
        // long tail of near-white pixels around every stroke, and counting
        // those would make this pass on a blank canvas with one grey dot.
        if (pixels[i] < 200) inked++;
      }
      image.dispose();
    });
    return inked;
  }

  testWidgets('takes its size from the ambient icon theme', (tester) async {
    await tester.pumpWidget(host());
    expect(tester.getSize(find.byType(NexSummariseIcon)), const Size(48, 48));
  });

  testWidgets('an explicit size wins over the theme', (tester) async {
    await tester.pumpWidget(host(size: 20));
    expect(tester.getSize(find.byType(NexSummariseIcon)), const Size(20, 20));
  });

  testWidgets('falls back to 24 when nothing says otherwise', (tester) async {
    // The same default [Icon] uses, so a row that sets neither still lines up.
    await tester.pumpWidget(
      host(theme: const IconThemeData(color: Colors.black)),
    );
    expect(tester.getSize(find.byType(NexSummariseIcon)), const Size(24, 24));
  });

  testWidgets('draws something, at the size a row of actions uses', (
    tester,
  ) async {
    // 20 is what the detail sheet's action row asks for. An icon that paints
    // itself off its own canvas, or into a hairline nobody can see, passes
    // every structural test there is — so this one looks at the pixels.
    await tester.pumpWidget(host(size: 20));
    expect(await inkedPixels(tester), greaterThan(20));
  });

  testWidgets('paints in the colour it is given', (tester) async {
    await tester.pumpWidget(host(size: 48, color: const Color(0xFF000000)));
    final dark = await inkedPixels(tester);

    // The same icon in the ground's own colour leaves nothing behind, which
    // is the only way to tell the colour is being used rather than ignored in
    // favour of a hardcoded one.
    await tester.pumpWidget(host(size: 48, color: const Color(0xFFFFFFFF)));
    expect(await inkedPixels(tester), lessThan(dark ~/ 10));
  });
}
