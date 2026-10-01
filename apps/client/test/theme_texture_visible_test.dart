import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_ui/nex_ui.dart';

/// A theme with a motif must leave the scaffold see-through, or the motif
/// is painted under an opaque page and never seen (1.92.0).
void main() {
  for (final id in ['paper', 'turquoise', 'forest', 'ocean', 'midnight']) {
    test('$id keeps the scaffold clear and the backdrop in its own colour', () {
      expect(nexThemeTexture(id), isNot(NexThemeTexture.none));
      for (final base in [
        nexLightTheme(transparentScaffold: true),
        nexDarkTheme(transparentScaffold: true),
      ]) {
        final theme = nexApplyThemePreset(base, id, null);
        expect(theme.scaffoldBackgroundColor.a, 0);
        expect(
          theme.extension<NexVisualStyle>()!.baseColor,
          theme.colorScheme.surface,
        );
      }
    });
  }

  test('without anything behind it a theme still fills its page', () {
    final theme = nexApplyThemePreset(nexLightTheme(), 'saffron', null);
    expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
  });
}
