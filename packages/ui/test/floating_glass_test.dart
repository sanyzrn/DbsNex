import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  for (final dark in [false, true]) {
    for (final highContrast in [false, true]) {
      testWidgets('floating glass pixels, dark=$dark contrast=$highContrast', (
        tester,
      ) async {
        final theme = dark
            ? nexDarkTheme(liquidGlass: true)
            : nexLightTheme(liquidGlass: true);
        Future<(Color, Color)> render(NexGlassMaterial material) async {
          const key = ValueKey('glass-pixels');
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(highContrast: highContrast),
                child: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: SizedBox(
                      width: 400,
                      height: 160,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const Row(
                            children: [
                              Expanded(
                                child: ColoredBox(
                                  color: Colors.black,
                                  child: SizedBox.expand(),
                                ),
                              ),
                              Expanded(
                                child: ColoredBox(
                                  color: Colors.white,
                                  child: SizedBox.expand(),
                                ),
                              ),
                            ],
                          ),
                          NexGlassSurface(
                            material: material,
                            child: const SizedBox.expand(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          return (await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(find.byKey(key))
                .toImage();
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            Color pixel(int x) {
              final offset = (80 * image.width + x) * 4;
              return Color.fromARGB(
                data.getUint8(offset + 3),
                data.getUint8(offset),
                data.getUint8(offset + 1),
                data.getUint8(offset + 2),
              );
            }

            final sampled = (pixel(80), pixel(320));
            image.dispose();
            return sampled;
          }))!;
        }

        final panel = await render(NexGlassMaterial.panel);
        final floating = await render(NexGlassMaterial.floating);
        final visible = (floating.$2.r - floating.$1.r).abs();
        if (highContrast) {
          expect(visible, lessThan(0.01));
          expect(find.byType(BackdropFilter), findsNothing);
        } else {
          expect(visible, greaterThan((panel.$2.r - panel.$1.r).abs() * 1.35));
          for (final ground in [floating.$1, floating.$2]) {
            expect(
              nexContrast(theme.colorScheme.onSurface, ground),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
