import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

/// The brief's timeout used to bind the network only (PERF-01): with no
/// provider and a model on the phone, a request that never came back held
/// the card's spinner, and every pull behind it, for good.
void main() {
  testWidgets('an on-device answer that never comes is given up on', (
    tester,
  ) async {
    final model = _SilentModel();
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(),
      localModel: model,
    );
    String? answer = 'pending';
    var done = false;
    unawaited(
      adapter
          .digest(
            'DUE in 6h | text | tax filing',
            lines: 2,
            timeout: CloudAIAdapter.ambientTimeout,
          )
          .then((value) {
            answer = value;
            done = true;
          }),
    );

    // Not at the network's twenty seconds: loading the weights alone can
    // take longer than that.
    await tester.pump(const Duration(seconds: 30));
    expect(done, isFalse);

    await tester.pump(CloudAIAdapter.localTimeoutFloor);
    expect(done, isTrue);
    expect(answer, isNull);
    model.never.complete(const ChatResponse(content: 'too late'));
  });
}

class _SilentModel implements ChatAdapter {
  final never = Completer<ChatResponse>();

  @override
  bool get available => true;

  @override
  Future<void>? warmUp() => null;

  @override
  Future<void>? release() => null;

  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) => never.future;
}
