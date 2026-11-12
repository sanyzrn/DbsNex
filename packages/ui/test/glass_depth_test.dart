import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// A saturated page colour no theme "corrects" by itself. If a pane turns it
/// grey, the films have eaten the page; if vibrancy is missing, its chroma
/// does not grow when the material is allowed to saturate the backdrop.
const _backdrop = Color(0xFF2F6FE0);

const _width = 390.0;
const _height = 844.0;

void main() {
  for (final dark in [false, true]) {
    testWidgets('the dock keeps the page colour alive and light on its edges '
        '(dark=$dark)', (tester) async {
      _usePhoneViewport(tester);
      final base = dark
          ? nexDarkTheme(liquidGlass: true)
          : nexLightTheme(liquidGlass: true);
      final visual = base.extension<NexVisualStyle>()!;

      // Full material, the same material without vibrancy (to isolate the
      // one variable), and a deliberately depthless version whose optics
      // and bevel are zeroed (to isolate the light itself).
      final fullShot = await _dockShot(tester, base);
      final plainShot = await _dockShot(
        tester,
        _withStyle(base, visual.copyWith(glassVibrancy: 1)),
      );
      final flatShot = await _dockShot(tester, _flat(base, visual));

      // The pane still shows the page's own colour...
      final fullPixel = _pixel(
        fullShot.data,
        fullShot.width,
        fullShot.x,
        fullShot.y,
      );
      expect(
        _chroma(fullPixel),
        greaterThan(15),
        reason: 'the dock turned a saturated page grey',
      );
      // ...and vibrancy gives that colour more voice, not less.
      final plainPixel = _pixel(
        plainShot.data,
        plainShot.width,
        plainShot.x,
        plainShot.y,
      );
      expect(
        _chroma(fullPixel),
        greaterThan(_chroma(plainPixel) + 2),
        reason:
            'vibrancy did not reach the dock: full '
            '${_chroma(fullPixel)} vs plain ${_chroma(plainPixel)}',
      );

      // ...and it is lit rather than flat: a vertical slice carries a lit
      // top edge, a readable middle, and a bounced bottom edge.
      final fullRange = _range(
        fullShot.data,
        fullShot.width,
        fullShot.x,
        fullShot.top,
        fullShot.bottom,
      );
      final flatRange = _range(
        flatShot.data,
        flatShot.width,
        flatShot.x,
        flatShot.top,
        flatShot.bottom,
      );
      expect(
        fullRange,
        greaterThan(0.05),
        reason: 'the dock has no light across its height',
      );
      expect(
        fullRange,
        greaterThan(flatRange + 0.04),
        reason:
            'the dock is as flat as a pane with every optical token off: '
            '$fullRange vs $flatRange',
      );
    });

    testWidgets('the dialog keeps the page colour alive and light on its edges '
        '(dark=$dark)', (tester) async {
      _usePhoneViewport(tester);
      final base = dark
          ? nexDarkTheme(liquidGlass: true)
          : nexLightTheme(liquidGlass: true);
      final visual = base.extension<NexVisualStyle>()!;

      final fullShot = await _dialogShot(tester, base);
      final plainShot = await _dialogShot(
        tester,
        _withStyle(base, visual.copyWith(glassVibrancy: 1)),
      );
      final flatShot = await _dialogShot(tester, _flat(base, visual));

      final fullPixel = _pixel(
        fullShot.data,
        fullShot.width,
        fullShot.x,
        fullShot.y,
      );
      expect(
        _chroma(fullPixel),
        greaterThan(15),
        reason: 'the dialog turned a saturated page grey',
      );
      final plainPixel = _pixel(
        plainShot.data,
        plainShot.width,
        plainShot.x,
        plainShot.y,
      );
      expect(
        _chroma(fullPixel),
        greaterThan(_chroma(plainPixel) + 2),
        reason:
            'vibrancy did not reach the dialog: full '
            '${_chroma(fullPixel)} vs plain ${_chroma(plainPixel)}',
      );

      final fullRange = _range(
        fullShot.data,
        fullShot.width,
        fullShot.x,
        fullShot.top,
        fullShot.bottom,
      );
      final flatRange = _range(
        flatShot.data,
        flatShot.width,
        flatShot.x,
        flatShot.top,
        flatShot.bottom,
      );
      expect(
        fullRange,
        greaterThan(0.04),
        reason: 'the dialog has no light across its height',
      );
      expect(
        fullRange,
        greaterThan(flatRange + 0.03),
        reason:
            'the dialog is as flat as a pane with every optical token off: '
            '$fullRange vs $flatRange',
      );
    });
  }
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(_width, _height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

ThemeData _withStyle(ThemeData theme, NexVisualStyle style) =>
    theme.copyWith(extensions: [style]);

ThemeData _flat(ThemeData theme, NexVisualStyle visual) => _withStyle(
  theme,
  visual.copyWith(
    glassVibrancy: 1,
    glassAura: Colors.transparent,
    glassBounce: Colors.transparent,
    glassSpecular: Colors.transparent,
    glassShade: Colors.transparent,
    glassHighlight: Colors.transparent,
    glassDepth: Colors.transparent,
    glassRim: Colors.transparent,
    glassBorder: Colors.transparent,
    glassShadow: Colors.transparent,
    glassEdgeWidth: 0,
    glassGrain: 0,
  ),
);

Widget _page(ThemeData theme, GlobalKey key, Widget body) => RepaintBoundary(
  key: key,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _backdrop),
          body,
        ],
      ),
    ),
  ),
);

Widget _dock() => NexNavigationDock(
  leading: const [SizedBox.shrink(), SizedBox.shrink()],
  capture: const SizedBox(width: 56, height: 56),
  trailing: const [SizedBox.shrink(), SizedBox.shrink()],
);

Future<_Shot> _dockShot(WidgetTester tester, ThemeData theme) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    _page(
      theme,
      key,
      Positioned(left: 0, right: 0, bottom: 40, child: Center(child: _dock())),
    ),
  );
  await tester.pumpAndSettle();
  final dock = tester.getRect(find.byType(NexNavigationDock));
  // The capsule is the lower 64 of the dock's 88; x sits inside its flat top
  // and clear of the empty leading slot and the centred capture button.
  final x = (dock.left + 80).round();
  final shot = await _capture(
    tester,
    key,
    x: x,
    y: (dock.top + 44).round(),
    top: (dock.top + 26).round(),
    bottom: (dock.bottom - 2).round(),
  );
  await tester.pumpWidget(const SizedBox());
  return shot;
}

Future<_Shot> _dialogShot(WidgetTester tester, ThemeData theme) async {
  final key = GlobalKey();
  await tester.pumpWidget(_page(theme, key, const SizedBox.expand()));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold));
  // Empty content keeps the panel's own material in the sample; a transparent
  // barrier leaves the page's colour visible behind the glass.
  unawaited(
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      builder: (_) =>
          const NexAlertDialog(content: SizedBox(width: 240, height: 220)),
    ),
  );
  await tester.pumpAndSettle();
  final pane = find.descendant(
    of: find.byType(NexAlertDialog),
    matching: find.byType(NexGlassSurface),
  );
  expect(pane, findsOneWidget);
  final rect = tester.getRect(pane);
  final shot = await _capture(
    tester,
    key,
    x: rect.center.dx.round(),
    y: rect.center.dy.round(),
    top: (rect.top + 2).round(),
    bottom: (rect.bottom - 2).round(),
  );
  await tester.pumpWidget(const SizedBox());
  return shot;
}

Future<_Shot> _capture(
  WidgetTester tester,
  GlobalKey key, {
  required int x,
  required int y,
  required int top,
  required int bottom,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = (await tester.runAsync(boundary.toImage))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final shot = _Shot(data, image.width, x, y, top, bottom);
  image.dispose();
  return shot;
}

class _Shot {
  _Shot(this.data, this.width, this.x, this.y, this.top, this.bottom);

  final ByteData data;
  final int width;
  final int x;
  final int y;
  final int top;
  final int bottom;
}

Color _pixel(ByteData data, int width, int x, int y) {
  final index = (y * width + x) * 4;
  return Color.fromARGB(
    data.getUint8(index + 3),
    data.getUint8(index),
    data.getUint8(index + 1),
    data.getUint8(index + 2),
  );
}

/// Difference between the strongest and weakest channel, 0…255. It survives
/// the films in a way hue does not: white and black both squash hue.
double _chroma(Color color) =>
    (math.max(color.r, math.max(color.g, color.b)) -
        math.min(color.r, math.min(color.g, color.b))) *
    255;

double _range(ByteData data, int width, int x, int top, int bottom) {
  var low = 1.0;
  var high = 0.0;
  for (var y = top; y <= bottom; y++) {
    final luminance = _pixel(data, width, x, y).computeLuminance();
    low = math.min(low, luminance);
    high = math.max(high, luminance);
  }
  return high - low;
}
