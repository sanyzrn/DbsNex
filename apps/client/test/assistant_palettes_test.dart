import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/theme_presets.dart';

/// The assistant can only offer the palettes its instructions name. They
/// named ten of fifteen until 2.6.27, and none of the six added then, so
/// "switch to Sunflower" had nothing to switch to.
void main() {
  test('the assistant is told every palette there is', () {
    for (final preset in nexThemePresets) {
      expect(
        RegExp('[(/\\s]${preset.id}[/;)]').hasMatch(assistantActionPrompt),
        isTrue,
        reason: preset.id,
      );
    }
  });
}
