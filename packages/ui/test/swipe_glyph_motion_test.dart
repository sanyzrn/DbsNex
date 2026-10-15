import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  for (final action in NexSwipeAction.values) {
    testWidgets('${action.name}: a held swipe pulses once, then rests', (
      tester,
    ) async {
      final key = GlobalKey();
      Future<void> show(
        double progress, {
        bool armed = false,
        bool still = false,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: still),
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: Colors.black,
                    child: NexSwipeActionGlyph(
                      action: action,
                      progress: progress,
                      armed: armed,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      Future<Uint8List> pixels() async => (await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
      await show(0);
      final resting = await pixels();
      await show(0.5);
      await tester.pump(const Duration(milliseconds: 80));
      expect(await pixels(), isNot(orderedEquals(resting)));
      // No new drag update: animation must continue while the finger pauses.
      await tester.pumpAndSettle();
      expect(await pixels(), orderedEquals(resting));
      await show(1, armed: true);
      await tester.pump(const Duration(milliseconds: 80));
      expect(await pixels(), isNot(orderedEquals(resting)));
      await tester.pumpAndSettle();
      expect(await pixels(), orderedEquals(resting));
      await show(0, still: true);
      await show(1, armed: true, still: true);
      await tester.pump(const Duration(milliseconds: 80));
      expect(await pixels(), orderedEquals(resting));
      expect(tester.takeException(), isNull);
    });
  }
}
