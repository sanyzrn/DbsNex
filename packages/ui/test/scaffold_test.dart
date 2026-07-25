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
}
