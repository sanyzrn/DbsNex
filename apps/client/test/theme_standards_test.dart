import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_ui/nex_ui.dart';

/// Every appearance (Light, Dark, Night), every palette, and a few picked
/// accents at the hard ends of the wheel, held to WCAG 2.2 on the pairs the
/// app actually draws: 4.5:1 for text on each surface it sits on, 3:1 for
/// boundaries and glyphs (1.4.11). The audit that found the 2.6.27 fixes —
/// the inverse capsule's accent, the classic light filled box, three light
/// palettes' outlines on filled boxes, a bright picked accent on cards.
void main() {
  test('every theme meets the contrast floors', () {
    final out = <String>[];
    for (final seed in [
      null,
      const Color(0xFFFFEB3B),
      const Color(0xFFB2FF59),
      const Color(0xFFE53935),
      const Color(0xFF7E57C2),
    ]) {
      final bases = <String, ThemeData Function()>{
        'light ${seed?.toARGB32().toRadixString(16)}': () =>
            nexSoftLightTheme(accentSeed: seed),
        'dark ${seed?.toARGB32().toRadixString(16)}': () =>
            nexSoftDarkTheme(accentSeed: seed),
        'night ${seed?.toARGB32().toRadixString(16)}': () =>
            nexOledNightTheme(accentSeed: seed),
      };
      for (final b in bases.entries) {
        for (final p in nexThemePresets) {
          final t = nexApplyThemePreset(b.value(), p.id, seed);
          final s = t.colorScheme;
          final fab = t.floatingActionButtonTheme;
          final grounds = {
            'page': t.scaffoldBackgroundColor.a == 0
                ? s.surface
                : t.scaffoldBackgroundColor,
            'surface': s.surface,
            'card': s.surfaceContainerLowest,
            'cHigh': s.surfaceContainerHigh,
            'cHighest': s.surfaceContainerHighest,
          };
          void check(String name, Color fg, Color bg, double min) {
            final r = nexContrastRatio(
              fg.withValues(alpha: 1),
              Color.alphaBlend(bg, grounds['page']!),
            );
            if (r < min) {
              out.add('${b.key}/${p.id}: $name ${r.toStringAsFixed(2)} < $min');
            }
          }

          for (final g in grounds.entries) {
            check('onSurface/${g.key}', s.onSurface, g.value, 4.5);
            check(
              'onSurfaceVariant/${g.key}',
              s.onSurfaceVariant,
              g.value,
              4.5,
            );
            check('primary/${g.key}', s.primary, g.value, 4.5);
            check('error/${g.key}', s.error, g.value, 4.5);
            check('outline/${g.key}', s.outline, g.value, 3);
          }
          check('onPrimary/primary', s.onPrimary, s.primary, 4.5);
          check(
            'onPrimaryContainer',
            s.onPrimaryContainer,
            s.primaryContainer,
            4.5,
          );
          check(
            'onSecondaryContainer',
            s.onSecondaryContainer,
            s.secondaryContainer,
            4.5,
          );
          check(
            'onTertiaryContainer',
            s.onTertiaryContainer,
            s.tertiaryContainer,
            4.5,
          );
          check('onErrorContainer', s.onErrorContainer, s.errorContainer, 4.5);
          check('onError/error', s.onError, s.error, 4.5);
          check('onInverse', s.onInverseSurface, s.inverseSurface, 4.5);
          check('inversePrimary', s.inversePrimary, s.inverseSurface, 4.5);
          check('secondary/card', s.secondary, s.surfaceContainerLowest, 4.5);
          check('tertiary/card', s.tertiary, s.surfaceContainerLowest, 4.5);
          if (fab.backgroundColor != null && fab.foregroundColor != null) {
            check('fabInk/fab', fab.foregroundColor!, fab.backgroundColor!, 3);
            check('fab/page', fab.backgroundColor!, grounds['page']!, 3);
          }
          for (final type in [
            'text',
            'voice',
            'photo',
            'checklist',
            'link',
            'file',
          ]) {
            check(
              'typeTint $type/card',
              nexNoteTypeTint(type, s),
              s.surfaceContainerLowest,
              3,
            );
          }
        }
      }
    }
    expect(out, isEmpty, reason: out.join('\n'));
  });
}
