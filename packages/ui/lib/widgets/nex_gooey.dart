import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paints [shapes] as one liquid: where two come close they reach for each
/// other and merge, and when they part a neck stretches and snaps.
///
/// The classic "gooey" technique, done on the canvas rather than with a
/// filtered widget subtree: every shape is drawn blurred into one layer, and
/// that layer is composited through a colour matrix that turns alpha into a
/// hard edge. Two blurs that overlap add up past the threshold before the
/// shapes themselves touch, which is the whole effect.
///
/// Cheap enough to run every frame of a short transition, because the layer
/// is bounded to [bounds] and the blur only ever touches a few small shapes —
/// never the screen. Callers paint the plain shape once the motion is over;
/// nothing here is meant to sit on screen at rest.
void nexPaintGooey(
  Canvas canvas, {
  required Rect bounds,
  required Color color,
  required Iterable<RRect> shapes,
  double softness = 7,
}) {
  // Alpha × 10, less 4.5 × 255: everything under ~45% coverage vanishes,
  // everything over ~55% is solid, and the 10% between is the anti-aliasing.
  const gain = 10.0;
  const threshold = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, gain, -4.5 * 255,
  ];
  // The threshold decides only *where* the liquid is. Its colour is laid on
  // afterwards through that shape: renderers disagree about whether a colour
  // matrix sees premultiplied pixels, and on the ones that do, the soft edge
  // of every blurred shape came out as a dark rim once its alpha was pushed
  // to opaque.
  canvas.saveLayer(bounds, Paint());
  canvas.saveLayer(
    bounds,
    Paint()..colorFilter = const ColorFilter.matrix(threshold),
  );
  final paint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, softness);
  for (final shape in shapes) {
    if (shape.width <= 0.5 || shape.height <= 0.5) continue;
    canvas.drawRRect(shape, paint);
  }
  canvas.restore();
  canvas.drawRect(
    bounds,
    Paint()
      ..color = color.withValues(alpha: 1)
      ..blendMode = BlendMode.srcIn,
  );
  canvas.restore();
}

/// A circle as the rounded rectangle [nexPaintGooey] takes.
RRect nexGooeyCircle(Offset center, double radius) => RRect.fromRectAndRadius(
  Rect.fromCircle(center: center, radius: math.max(radius, 0)),
  Radius.circular(math.max(radius, 0)),
);
