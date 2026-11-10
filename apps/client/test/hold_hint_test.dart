import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';

import 'support/nex_harness.dart';

/// The pill that teaches holding + for the assistant only appears while the
/// assistant can actually answer: with intelligence off (the default), the
/// taught gesture ends in the "turn it on" banner — a strange first lesson.
void main() {
  testWidgets('the hold hint waits until the assistant can answer', (
    tester,
  ) async {
    // Completing the tour (which the harness does) already counts as having
    // seen the hint; the key has to exist for the pill to be due at all.
    final h = await NexTestHarness.create(
      preferences: {'home.capture_hold_hint_seen': false},
    );
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.textContaining('Hold + for the assistant'), findsNothing);

    await h.preferences.setAiEnabled(true);
    await h.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.textContaining('Hold + for the assistant'), findsOneWidget);
  });
}
