import 'dart:typed_data' show Float32List, Float64List, Int32List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// Timing harness for the app's static backdrop painters — the theme motifs
/// every app frame sits on. Not a correctness test: it prints timings.
///
/// Run: flutter test test/perf/nex_backdrop_bench_test.dart
///
/// What it measures, at a phone-sized 390x844 logical frame:
///  * record — the CPU cost of running the painter's paint() (the UI thread
///    pays this on every scroll frame when the painter shares a repaint
///    boundary with the scrolling content);
///  * raster — software rasterization of the recorded picture at 3x device
///    pixel ratio, a proxy for the GPU work the raster thread pays every
///    frame (Impeller has no raster cache, so an unchanged static picture is
///    re-rasterized each frame the screen moves);
///  * ops — the number of canvas commands in the picture.
void main() {
  test('texture painters: ops, record and raster cost', () async {
    const frame = ui.Size(390, 844);
    const dpr = 3.0;
    final ink = const Color(0x22000000);
    final out = <String>[];

    for (final texture in NexThemeTexture.values) {
      final painter = NexTexturePainter(
        texture: texture,
        ink: ink,
        pixelRatio: dpr,
      );
      // The first paint rasterizes the motif into the cached image (the
      // one-time cost of entering a theme or rotating the screen); every
      // paint after that draws that image.
      final firstUs = _bestOf(() => _record(painter, frame).dispose(), n: 1);
      final opCount = _countOps(painter, frame);
      final recordUs = _bestOf(() => _record(painter, frame).dispose(), n: 20);
      final rasterUs = await _rasterBestOf(painter, frame, dpr, n: 8);
      out.add(
        'BENCH ${texture.name.padRight(10)} '
        'ops=${opCount.toString().padLeft(5)} '
        'warmRecord=${recordUs.toStringAsFixed(0).padLeft(6)}us '
        'firstRecord=${firstUs.toStringAsFixed(0).padLeft(7)}us '
        'raster3x=${rasterUs.toStringAsFixed(0).padLeft(7)}us',
      );
    }

    // ignore: avoid_print
    print(out.join('\n'));
    expect(out.length, NexThemeTexture.values.length);
  });

  testWidgets('localToGlobal: to root vs to a near ancestor', (tester) async {
    // The sticky-day walk asks every mounted row for its position on every
    // scroll frame. Each mark's box sits deep in the tree; the walk pays a
    // matrix walk from the box to the destination render object. To the root
    // is the whole app's depth; to the scroll viewport is a few levels.
    const depth = 20;
    const marks = 30;
    final keys = List.generate(marks, (i) => GlobalKey());

    Widget nest(Widget child, int level) => level == 0
        ? child
        : nest(
            Padding(
              padding: const EdgeInsets.all(1),
              child: Center(child: child),
            ),
            level - 1,
          );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final key in keys)
                  nest(SizedBox(key: key, width: 50, height: 50), depth),
              ],
            ),
          ),
        ),
      ),
    );

    final boxes = [
      for (final key in keys)
        key.currentContext!.findRenderObject()! as RenderBox,
    ];
    final viewport = RenderAbstractViewport.maybeOf(boxes.first);

    double walkToRoot() {
      var top = double.infinity;
      for (final box in boxes) {
        final y = box.localToGlobal(Offset.zero).dy;
        if (y < top) top = y;
      }
      return top;
    }

    double walkToViewport() {
      var top = double.infinity;
      for (final box in boxes) {
        final y = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        if (y < top) top = y;
      }
      return top;
    }

    final rootUs = _bestOf(walkToRoot, n: 100);
    final viewportUs = _bestOf(walkToViewport, n: 100);
    // Same answer, shorter walk.
    expect(walkToRoot(), walkToViewport());
    // ignore: avoid_print
    print(
      'BENCH localToGlobal x$marks '
      'root=${rootUs.toStringAsFixed(1)}us '
      'viewport=${viewportUs.toStringAsFixed(1)}us '
      'saved=${(100 - viewportUs / rootUs * 100).toStringAsFixed(0)}%',
    );
  });
}

ui.Picture _record(CustomPainter painter, ui.Size size) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(3.0); // Record at device scale for the raster measurement.
  painter.paint(canvas, size);
  return recorder.endRecording();
}

int _countOps(CustomPainter painter, ui.Size size) {
  var ops = 0;
  final recorder = ui.PictureRecorder();
  final canvas = _CountingCanvas(recorder, () => ops++, () {});
  painter.paint(canvas, size);
  recorder.endRecording().dispose();
  return ops;
}

Future<double> _rasterBestOf(
  CustomPainter painter,
  ui.Size size,
  double dpr, {
  int n = 8,
}) async {
  final w = (size.width * dpr).round();
  final h = (size.height * dpr).round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(dpr);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  var best = double.infinity;
  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    final image = await picture.toImage(w, h);
    sw.stop();
    image.dispose();
    if (sw.elapsedMicroseconds < best) {
      best = sw.elapsedMicroseconds.toDouble();
    }
  }
  picture.dispose();
  return best;
}

double _bestOf(void Function() body, {int n = 20}) {
  // Warm-up.
  for (var i = 0; i < 5; i++) {
    body();
  }
  var best = double.infinity;
  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    final us = sw.elapsedMicroseconds;
    if (us < best) best = us.toDouble();
  }
  return best;
}

/// Counts canvas commands by intercepting each draw call: forwards every
/// member of [ui.Canvas] (an abstract class here) to a real canvas.
class _CountingCanvas implements ui.Canvas {
  _CountingCanvas(ui.PictureRecorder recorder, this.onDraw, this.onLayer)
    : inner = ui.Canvas(recorder);

  final ui.Canvas inner;
  final void Function() onDraw;
  final void Function() onLayer;

  @override
  void save() {
    onLayer();
    inner.save();
  }

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) {
    onLayer();
    inner.saveLayer(bounds, paint);
  }

  @override
  void restore() => inner.restore();

  @override
  void restoreToCount(int count) => inner.restoreToCount(count);

  @override
  int getSaveCount() => inner.getSaveCount();

  @override
  void translate(double dx, double dy) => inner.translate(dx, dy);

  @override
  void scale(double sx, [double? sy]) => inner.scale(sx, sy);

  @override
  void rotate(double radians) => inner.rotate(radians);

  @override
  void skew(double sx, double sy) => inner.skew(sx, sy);

  @override
  void transform(Float64List matrix4) => inner.transform(matrix4);

  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => inner.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);

  @override
  void clipRRect(ui.RRect rrect, {bool doAntiAlias = true}) =>
      inner.clipRRect(rrect, doAntiAlias: doAntiAlias);

  @override
  void clipRSuperellipse(ui.RSuperellipse rse, {bool doAntiAlias = true}) =>
      inner.clipRSuperellipse(rse, doAntiAlias: doAntiAlias);

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) =>
      inner.clipPath(path, doAntiAlias: doAntiAlias);

  @override
  void drawColor(ui.Color color, ui.BlendMode blendMode) =>
      inner.drawColor(color, blendMode);

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, ui.Paint paint) {
    onDraw();
    inner.drawLine(p1, p2, paint);
  }

  @override
  void drawPaint(ui.Paint paint) {
    onDraw();
    inner.drawPaint(paint);
  }

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) {
    onDraw();
    inner.drawRect(rect, paint);
  }

  @override
  void drawRRect(ui.RRect rrect, ui.Paint paint) {
    onDraw();
    inner.drawRRect(rrect, paint);
  }

  @override
  void drawDRRect(ui.RRect outer, ui.RRect inner, ui.Paint paint) {
    onDraw();
    this.inner.drawDRRect(outer, inner, paint);
  }

  @override
  void drawRSuperellipse(ui.RSuperellipse rse, ui.Paint paint) {
    onDraw();
    inner.drawRSuperellipse(rse, paint);
  }

  @override
  void drawOval(ui.Rect rect, ui.Paint paint) {
    onDraw();
    inner.drawOval(rect, paint);
  }

  @override
  void drawCircle(ui.Offset c, double radius, ui.Paint paint) {
    onDraw();
    inner.drawCircle(c, radius, paint);
  }

  @override
  void drawArc(
    ui.Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    ui.Paint paint,
  ) {
    onDraw();
    inner.drawArc(rect, startAngle, sweepAngle, useCenter, paint);
  }

  @override
  void drawPath(ui.Path path, ui.Paint paint) {
    onDraw();
    inner.drawPath(path, paint);
  }

  @override
  void drawImage(ui.Image image, ui.Offset offset, ui.Paint paint) {
    onDraw();
    inner.drawImage(image, offset, paint);
  }

  @override
  void drawImageRect(ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
    onDraw();
    inner.drawImageRect(image, src, dst, paint);
  }

  @override
  void drawImageNine(
    ui.Image image,
    ui.Rect center,
    ui.Rect dst,
    ui.Paint paint,
  ) {
    onDraw();
    inner.drawImageNine(image, center, dst, paint);
  }

  @override
  void drawPicture(ui.Picture picture) {
    onDraw();
    inner.drawPicture(picture);
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) {
    onDraw();
    inner.drawParagraph(paragraph, offset);
  }

  @override
  void drawPoints(
    ui.PointMode pointMode,
    List<ui.Offset> points,
    ui.Paint paint,
  ) {
    onDraw();
    inner.drawPoints(pointMode, points, paint);
  }

  @override
  void drawRawPoints(
    ui.PointMode pointMode,
    Float32List points,
    ui.Paint paint,
  ) {
    onDraw();
    inner.drawRawPoints(pointMode, points, paint);
  }

  @override
  void drawVertices(
    ui.Vertices vertices,
    ui.BlendMode blendMode,
    ui.Paint paint,
  ) {
    onDraw();
    inner.drawVertices(vertices, blendMode, paint);
  }

  @override
  void drawAtlas(
    ui.Image atlas,
    List<ui.RSTransform> transforms,
    List<ui.Rect> rects,
    List<ui.Color>? colors,
    ui.BlendMode? blendMode,
    ui.Rect? cullRect,
    ui.Paint paint,
  ) {
    onDraw();
    inner.drawAtlas(
      atlas,
      transforms,
      rects,
      colors,
      blendMode,
      cullRect,
      paint,
    );
  }

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    ui.BlendMode? blendMode,
    ui.Rect? cullRect,
    ui.Paint paint,
  ) {
    onDraw();
    inner.drawRawAtlas(
      atlas,
      rstTransforms,
      rects,
      colors,
      blendMode,
      cullRect,
      paint,
    );
  }

  @override
  void drawShadow(
    ui.Path path,
    ui.Color color,
    double elevation,
    bool transparentOccluder,
  ) {
    onDraw();
    inner.drawShadow(path, color, elevation, transparentOccluder);
  }

  @override
  ui.Rect getLocalClipBounds() => inner.getLocalClipBounds();

  @override
  ui.Rect getDestinationClipBounds() => inner.getDestinationClipBounds();

  @override
  Float64List getTransform() => inner.getTransform();
}
