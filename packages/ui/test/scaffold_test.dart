import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  test('design tokens match mockup.html / 05-design.md', () {
    expect(NexColors.bgPrimaryLight.toARGB32(), 0xFFFFFFFF);
    expect(NexColors.bgPrimaryDark.toARGB32(), 0xFF0A0A0A);
    // Mockup --text:#111113 (authoritative visual reference).
    expect(NexColors.textPrimaryLight.toARGB32(), 0xFF111113);
    expect(NexColors.textPrimaryDark.toARGB32(), 0xFFFAFAFA);
    // Deliberately not the mockup's --text-soft (#8B8B90): that is 3.39:1 on
    // white and fails the 4.5:1 body-text floor 05-design.md sets for itself.
    // #68686D is 5.54:1. See the note under the token table.
    expect(NexColors.textSecondaryLight.toARGB32(), 0xFF68686D);
    expect(NexColors.borderLight.toARGB32(), 0xFFEBEAE8);
    expect(NexColors.cardRadius, 22);
    expect(nexCaptureFabSize, 64);
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
