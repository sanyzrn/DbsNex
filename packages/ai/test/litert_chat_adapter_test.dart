import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/nex_ai.dart';

/// What can be proved without a phone.
///
/// The inference itself cannot be: LiteRT-LM is a platform plugin behind a
/// method channel, and the weights are 2.6 GB. What *is* worth pinning down is
/// the behaviour around it — the part that decides whether the app asks the
/// model anything at all, and the part that decides how much of a conversation
/// gets re-processed. Both are ours, and both are where a mistake is silent.
void main() {
  group('availability is a state, not an error', () {
    test(
      'a model that is not downloaded yet answers null, before awaiting',
      () {
        final adapter = LiteRtChatAdapter(
          modelPath: '/does/not/exist/gemma-4-e2b.litertlm',
        );

        // Null rather than a thrown or a failed Future: every AIAdapter method
        // follows this convention, and callers check before they await.
        expect(
          adapter.sendMessage(const [
            ChatMessage(role: ChatRole.user, content: 'hello'),
          ]),
          isNull,
        );
        expect(adapter.available, isFalse);
      },
    );

    test('an empty path is unavailable rather than a filesystem question', () {
      expect(LiteRtChatAdapter(modelPath: '').available, isFalse);
    });

    test('an empty history is never sent anywhere', () {
      final adapter = LiteRtChatAdapter(modelPath: '');
      expect(adapter.sendMessage(const []), isNull);
    });
  });

  group('the scope ceiling is applied by the adapter, not by its callers', () {
    test('withScopeCeiling prepends exactly one system message', () {
      final once = withScopeCeiling(const [
        ChatMessage(role: ChatRole.user, content: 'hi'),
      ]);
      expect(once.first.role, ChatRole.system);
      expect(once.first.content, nexChatScopeCeilingPrompt);

      // Applying it again must not stack a second one — the adapter calls this
      // on every message, so a non-idempotent version would grow the prompt
      // by the whole ceiling on every turn of a conversation.
      final twice = withScopeCeiling(once);
      expect(
        twice.where((ChatMessage m) => m.role == ChatRole.system),
        hasLength(1),
      );
    });
  });

  test(
    'the placeholder it replaces still answers, and says it is one',
    () async {
      // Kept bound until model management exists, so the "ai" flavor is never
      // left with nothing behind ChatAdapterBinding.
      final reply = await const PlaceholderLocalChatAdapter().sendMessage(
        const [ChatMessage(role: ChatRole.user, content: 'hello')],
      )!;
      expect(reply.content, contains('Phase 1'));
    },
  );
}
