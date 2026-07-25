import 'package:nex_ai/nex_ai.dart';
import 'package:test/test.dart';

void main() {
  test('nex_ai resolves under plain dart test (no Flutter harness)', () {
    expect(packageName, 'nex_ai');
  });
}
