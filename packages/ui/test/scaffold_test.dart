import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  test('design tokens match 05-design.md', () {
    expect(NexColors.bgPrimaryLight.toARGB32(), 0xFFFFFFFF);
    expect(NexColors.bgPrimaryDark.toARGB32(), 0xFF0A0A0A);
    expect(NexColors.textPrimaryLight.toARGB32(), 0xFF0A0A0A);
    expect(NexColors.textPrimaryDark.toARGB32(), 0xFFFAFAFA);
    expect(nexMinTapTarget, 44);
  });

  test('Comfort Mode token deltas match 05-design.md table', () {
    expect(NexColors.bgPrimaryLightComfort.toARGB32(), 0xFFF7F1E6);
    expect(NexColors.bgPrimaryDarkComfort.toARGB32(), 0xFF17130F);
    expect(NexColors.textPrimaryLightComfort.toARGB32(), 0xFF2E2A22);
    expect(NexColors.textPrimaryDarkComfort.toARGB32(), 0xFFD9CFC0);
  });

  test('Comfort Mode retains WCAG AA contrast in both themes', () {
    expect(
      nexContrastRatio(
        NexColors.textPrimaryLightComfort,
        NexColors.bgPrimaryLightComfort,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      nexContrastRatio(
        NexColors.textPrimaryDarkComfort,
        NexColors.bgPrimaryDarkComfort,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });
}
