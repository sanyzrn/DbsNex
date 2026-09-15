import 'package:nex_ai/nex_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nex_ai exports OnDeviceAIAdapter', () {
    const adapter = OnDeviceAIAdapter();
    // What it does *not* offer, which is the thing worth asserting about this
    // adapter. It used to carry an `embeddingDims` of 32 and fill that many
    // doubles from a SHA-256 digest — a vector with no similarity structure,
    // stored and then shown to the user under a "semantic matches" heading.
    // The field is gone with the function that needed it.
    expect(adapter.embed('anything'), isNull);
    expect(
      adapter.transcribe(const AudioRef(mediaUri: 'a')),
      isNull,
    );
  });
}
