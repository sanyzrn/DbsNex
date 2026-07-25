import 'package:nex_ai/nex_ai.dart';
import 'package:test/test.dart';

void main() {
  test('nex_ai exports OnDeviceAIAdapter', () {
    const adapter = OnDeviceAIAdapter();
    expect(adapter.embeddingDims, 32);
  });
}
