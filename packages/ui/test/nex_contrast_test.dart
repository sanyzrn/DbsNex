import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// Text and focus marks clear their contrast floors whatever the accent.
void main() {
  const white = Color(0xFFFFFFFF);
  const darkCard = Color(0xFF1E1E1E);

  test('a pale custom accent is darkened to 3:1 on white (LOC-08)', () {
    final palette = nexAccentPaletteFrom(const Color(0xFFFFD24A));
    expect(nexContrast(palette.light, white), greaterThanOrEqualTo(3));
    expect(nexContrast(palette.strongLight, white), greaterThanOrEqualTo(4.5));
    expect(nexContrast(palette.dark, darkCard), greaterThanOrEqualTo(3));
    expect(
      nexContrast(palette.strongDark, darkCard),
      greaterThanOrEqualTo(4.5),
    );
    // Same hue, only lightness moved.
    expect(
      HSLColor.fromColor(palette.light).hue,
      closeTo(HSLColor.fromColor(const Color(0xFFFFD24A)).hue, 1),
    );
  });

  test('a colour that already clears the floor is left alone', () {
    const ink = Color(0xFF123456);
    expect(nexReadableOn(ink, white), ink);
  });

  test('quiet buttons and links in the classic light theme read at 4.5:1 '
      '(LOC-07)', () {
    final theme = nexLightTheme();
    final label = theme.textButtonTheme.style!.foregroundColor!.resolve({})!;
    expect(nexContrast(label, white), greaterThanOrEqualTo(4.5));
  });

  test('the dark theme draws errors readably (LOC-02)', () {
    final theme = nexDarkTheme();
    expect(
      nexContrast(theme.colorScheme.error, darkCard),
      greaterThanOrEqualTo(4.5),
    );
    expect(nexLightTheme().colorScheme.error, NexColors.error);
  });

  test(
    'Persian text in the English theme falls back to Vazirmatn (LOC-04)',
    () {
      expect(
        nexLightTheme().textTheme.bodyLarge!.fontFamilyFallback,
        contains(nexPersianFont),
      );
      expect(
        nexDarkTheme(
          fontFamily: nexPersianFont,
        ).textTheme.bodyLarge!.fontFamilyFallback,
        contains(nexLatinFont),
      );
    },
  );
}
