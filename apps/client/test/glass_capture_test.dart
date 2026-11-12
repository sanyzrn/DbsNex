// Renders the real app with the rebuilt Liquid Glass on, in every shipped
// appearance, and saves phone-sized captures for visual inspection.
// Run: flutter test --dart-define=NEX_GLASS_CAPTURE=<dir> test/glass_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  // Real app captures for visual inspection of the material. Without the
  // define the tests still run (they exercise the glass build end to end)
  // and only the PNG write is skipped, so CI counts real tests here.
  const output = String.fromEnvironment('NEX_GLASS_CAPTURE');
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in NexAppearanceMode.values) {
    if (mode == NexAppearanceMode.system) continue;
    testWidgets('${mode.name} glass home', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = await NexTestHarness.create(onboarded: true);
      addTearDown(h.dispose);
      await h.preferences.setAppearanceMode(mode);
      await h.preferences.setLiquidGlass(true);
      await h.db.captureText('A glass caption to sit behind the bar');
      await h.db.captureText('Another line of the library, mid screen');
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: h.app()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NexGlassBar), findsOneWidget);
      if (output.isEmpty) return;
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/glass_${mode.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
