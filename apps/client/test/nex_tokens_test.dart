import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  test('caption token pairs clear WCAG AA', () {
    expect(nexContrastRatio(
      NexColors.textSecondaryLight,
      NexColors.bgPrimaryLight,
    ), greaterThanOrEqualTo(4.5));
    expect(nexContrastRatio(
      NexColors.textSecondaryLightComfort,
      NexColors.bgPrimaryLightComfort,
    ), greaterThanOrEqualTo(4.5));
    expect(nexContrastRatio(
      NexColors.textSecondaryDark,
      NexColors.bgPrimaryDark,
    ), greaterThanOrEqualTo(4.5));
  });
}