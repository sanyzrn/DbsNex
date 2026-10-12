import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

const _types = ['text', 'checklist', 'link', 'voice', 'photo', 'file'];

const _seeds = <Color?>[
  null,
  Color(0xFFD9A441),
  Color(0xFF2E9E5B),
  Color(0xFFC2456A),
  Color(0xFF7A5AF8),
  Color(0xFFE5D33A),
  Color(0xFF777777),
];

void main() {
  for (final seed in _seeds) {
    for (final dark in [false, true]) {
      final scheme =
          (dark
                  ? nexDarkTheme(accentSeed: seed)
                  : nexLightTheme(accentSeed: seed))
              .colorScheme;
      final label =
          '${seed?.toARGB32().toRadixString(16) ?? 'default'} '
          '${dark ? 'dark' : 'light'}';

      test('$label: text is the accent, at most a shade deeper', () {
        for (final type in ['text', null]) {
          final tint = HSLColor.fromColor(nexNoteTypeTint(type, scheme));
          final accent = HSLColor.fromColor(scheme.primary);
          expect(tint.hue, closeTo(accent.hue, 1), reason: '$type');
          expect(tint.saturation, closeTo(accent.saturation, 0.02));
        }
      });

      test('$label: every type reads at 3:1 on its square', () {
        for (final type in _types) {
          final tint = nexNoteTypeTint(type, scheme);
          expect(
            nexContrast(tint, nexNoteTypeWash(type, scheme)),
            greaterThanOrEqualTo(3),
            reason: type,
          );
        }
      });

      if (seed != const Color(0xFF777777)) {
        test('$label: the six are six different colours', () {
          final tints = {for (final t in _types) nexNoteTypeTint(t, scheme)};
          expect(tints, hasLength(_types.length));
        });
      }
    }
  }

  test('the family follows the accent: another accent, other colours', () {
    final blue = nexLightTheme().colorScheme;
    final amber = nexLightTheme(
      accentSeed: const Color(0xFFD9A441),
    ).colorScheme;
    for (final type in _types) {
      expect(
        nexNoteTypeTint(type, blue),
        isNot(nexNoteTypeTint(type, amber)),
        reason: type,
      );
    }
  });

  test('every turned type stays near the accent on the wheel', () {
    final scheme = nexLightTheme(
      accentSeed: const Color(0xFF2E9E5B),
    ).colorScheme;
    final accent = HSLColor.fromColor(scheme.primary).hue;
    for (final type in ['checklist', 'link', 'voice', 'photo']) {
      final hue = HSLColor.fromColor(nexNoteTypeTint(type, scheme)).hue;
      final apart = ((hue - accent + 540) % 360 - 180).abs();
      expect(apart, inInclusiveRange(20, 90), reason: type);
    }
  });
}
