import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The WCAG contrast ratio between two opaque colours, 1 to 21.
double nexContrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [color], darkened on a light [ground] or lightened on a dark one — hue
/// kept — just far enough to reach [ratio] against it.
///
/// The accent is picked for how it looks, not measured for what it is
/// drawn on, and two places read it as text or as the only sign of focus:
/// link text and quiet buttons on the classic light theme (LOC-07), and any
/// accent someone picks themselves (LOC-08). A colour that already clears
/// [ratio] comes back unchanged.
Color nexReadableOn(Color color, Color ground, {double ratio = 4.5}) {
  final opaqueGround = ground.withValues(alpha: 1);
  if (nexContrast(color, opaqueGround) >= ratio) return color;
  final darken = opaqueGround.computeLuminance() > 0.18;
  var hsl = HSLColor.fromColor(color.withValues(alpha: 1));
  for (var step = 0; step < 100; step++) {
    final lightness = (hsl.lightness + (darken ? -0.01 : 0.01)).clamp(0.0, 1.0);
    hsl = hsl.withLightness(lightness);
    final candidate = hsl.toColor();
    if (nexContrast(candidate, opaqueGround) >= ratio ||
        lightness == 0 ||
        lightness == 1) {
      return candidate.withValues(alpha: color.a);
    }
  }
  return hsl.toColor().withValues(alpha: color.a);
}
