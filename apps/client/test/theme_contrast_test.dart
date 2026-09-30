import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_ui/nex_ui.dart';

double _luminance(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _contrast(Color a, Color b) {
  final x = _luminance(a), y = _luminance(b);
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

/// Every palette, both brightnesses: an icon on a filled button is readable.
///
/// The report: on every palette but the classic one the capture arrow, the
/// vault's add buttons, the saved-messages send and a voice note's play
/// button drew a grey icon on a coloured button. A global icon colour in the
/// palette won over the button's own foreground; it measured about 1:1.
void main() {
  for (final preset in nexThemePresets) {
    for (final dark in [false, true]) {
      testWidgets(
        '${preset.id} ${dark ? 'dark' : 'light'}: a filled button\'s icon',
        (tester) async {
          final seed = nexThemePresetSeed(preset.id);
          final base = dark
              ? nexDarkTheme(accentSeed: seed)
              : nexLightTheme(accentSeed: seed);
          await tester.pumpWidget(
            MaterialApp(
              theme: nexApplyThemePreset(base, preset.id, seed),
              home: Scaffold(
                body: Center(
                  child: IconButton.filled(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ),
              ),
            ),
          );
          final button = tester.widget<Material>(
            find
                .descendant(
                  of: find.byType(IconButton),
                  matching: find.byType(Material),
                )
                .first,
          );
          final icon = IconTheme.of(
            tester.element(find.byIcon(Icons.arrow_upward)),
          );
          // WCAG's 3:1 for a graphical object that has to be seen.
          expect(
            _contrast(button.color!, icon.color!),
            greaterThanOrEqualTo(3),
          );
        },
      );
    }
  }
}
