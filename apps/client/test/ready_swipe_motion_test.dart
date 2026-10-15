import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:nex_client/widgets/ready_swipe_icon.dart';
import 'package:lottie/lottie.dart';

void main() {
  for (final action in NexSwipeAction.values) {
    testWidgets(
      '${action.name}: motion reverses and reduced motion stays still',
      (tester) async {
        final boundaryKey = GlobalKey();
        await tester.runAsync(() async {
          await Lottie.cache.putIfAbsent(
            AssetLottie(NexReadySwipeIcon.asset(action)),
            () => AssetLottie(NexReadySwipeIcon.asset(action)).load(),
          );
        });
        Future<void> paint(double progress, {bool still = false}) async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: still),
                child: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: ColoredBox(
                      color: Colors.black,
                      child: NexSwipeGlyphTheme(
                        builder: (context, action, progress, armed, color) =>
                            NexReadySwipeIcon(
                              action: action,
                              progress: progress,
                              color: color,
                            ),
                        child: NexSwipeActionGlyph(
                          action: action,
                          progress: progress,
                          armed: progress >= 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<Uint8List> pixels() async => (await tester.runAsync(() async {
          final image =
              await (boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        }))!;

        await paint(0);
        final resting = await pixels();
        await paint(0.55);
        expect(await pixels(), isNot(orderedEquals(resting)));
        await paint(0);
        expect(await pixels(), orderedEquals(resting));
        await paint(0, still: true);
        final reduced = await pixels();
        await paint(1, still: true);
        expect(await pixels(), orderedEquals(reduced));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
