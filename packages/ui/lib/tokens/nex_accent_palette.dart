import 'package:flutter/material.dart';

import 'nex_contrast.dart';

/// The four accent shades a theme actually needs, derived from one seed.
///
/// Nex's colour system is "declared, not seeded" for the neutral ramp (see
/// [NexRadius]'s sibling comment in nex_tokens.dart) — that stays. This is
/// narrower: the *accent* used to be four independently hand-picked hex
/// values (light, a darker "strong" shade for emphasis, and lighter tints of
/// both for dark backgrounds), so letting someone recolour it meant asking
/// for four numbers that had to stay in proportion by hand. One seed and a
/// fixed tonal ramp — the same idea Material's tonal palettes use, just
/// narrowed to the one role Nex actually varies — reproduces that
/// relationship for whatever hue someone picks.
class NexAccentPalette {
  const NexAccentPalette({
    required this.light,
    required this.strongLight,
    required this.dark,
    required this.strongDark,
  });

  /// The accent as drawn on a light background.
  final Color light;

  /// A darker step of the same hue, for text/fills that need more contrast
  /// than [light] on a light background.
  final Color strongLight;

  /// The accent as drawn on a dark background — lighter, so it still reads
  /// against a near-black ground instead of going murky.
  final Color dark;

  /// [dark]'s own emphasis step, lighter still.
  final Color strongDark;
}

/// Fixed lightness targets, one per role — chosen to land close to the
/// shipped defaults (`NexColors.accent*`) when [seed] is that same blue, so
/// picking the default back is a no-op rather than a visible shift.
const _lightTone = 0.55;
const _strongLightTone = 0.44;
const _darkTone = 0.72;
const _strongDarkTone = 0.82;

/// Derives [NexAccentPalette] from a single [seed] colour.
///
/// Hue is preserved exactly; lightness is pinned to each role's tone above;
/// saturation carries over as-is for the light-background roles and eases
/// back slightly for the dark-background ones, where the same saturation at
/// a much higher lightness reads as neon rather than as the same colour.
NexAccentPalette nexAccentPaletteFrom(Color seed) {
  final hsl = HSLColor.fromColor(seed);

  Color tone(double lightness, {double saturationDelta = 0}) => hsl
      .withLightness(lightness.clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + saturationDelta).clamp(0.0, 1.0))
      .toColor();

  // Pinned lightness is not pinned contrast: a yellow at 0.55 is about
  // 1.5:1 on white, and the accent is the caret, the focus ring and the
  // active filter (LOC-08). Each role is walked darker on the light card or
  // lighter on the dark one until it clears the 3:1 floor for those marks,
  // and the strong roles, which carry text, until they clear 4.5:1. A seed
  // that already clears them — the shipped blue among them — is untouched.
  const lightCard = Color(0xFFFFFFFF);
  const darkCard = Color(0xFF1E1E1E);
  return NexAccentPalette(
    light: nexReadableOn(tone(_lightTone), lightCard, ratio: 3),
    strongLight: nexReadableOn(tone(_strongLightTone), lightCard),
    dark: nexReadableOn(
      tone(_darkTone, saturationDelta: -0.05),
      darkCard,
      ratio: 3,
    ),
    strongDark: nexReadableOn(
      tone(_strongDarkTone, saturationDelta: -0.08),
      darkCard,
    ),
  );
}
