import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

void main() {
  test('nex_data resolves under plain dart test (no Flutter harness)', () {
    expect(packageName, 'nex_data');
  });
}
