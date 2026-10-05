import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// Counts how often it was asked to let go of its memory.
class _CountingModel implements ChatAdapter {
  int releases = 0;

  @override
  bool get available => true;

  @override
  Future<void>? warmUp() => null;

  @override
  Future<void>? release() {
    releases++;
    return null;
  }

  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) => null;
}

void main() {
  testWidgets('memory pressure in the foreground frees the on-device model', (
    tester,
  ) async {
    final model = _CountingModel();
    ChatAdapterBinding.bind(model);
    addTearDown(ChatAdapterBinding.reset);
    await pumpNexApp(tester);

    expect(model.releases, 0);
    tester.binding.handleMemoryPressure();
    expect(model.releases, 1);
  });

  testWidgets('going to the background frees it too', (tester) async {
    final model = _CountingModel();
    ChatAdapterBinding.bind(model);
    addTearDown(ChatAdapterBinding.reset);
    await pumpNexApp(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(model.releases, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });
}
