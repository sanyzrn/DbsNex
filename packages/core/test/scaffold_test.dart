import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  test('nex_core resolves under plain dart test (no Flutter harness)', () {
    expect(packageName, 'nex_core');
  });
}
