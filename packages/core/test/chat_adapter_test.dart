import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

class _FakeChatAdapter implements ChatAdapter {
  List<ChatMessage>? lastHistory;

  @override
  bool get available => true;

  @override
  Future<void>? warmUp() => null;

  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) {
    lastHistory = history;
    return Future.value(const ChatResponse(content: 'ok'));
  }
}

void main() {
  tearDown(ChatAdapterBinding.reset);

  group('NullChatAdapter', () {
    test('sendMessage returns null (unavailable, not an error)', () {
      const adapter = NullChatAdapter();
      expect(
        adapter.sendMessage(const [
          ChatMessage(role: ChatRole.user, content: 'hi'),
        ]),
        isNull,
      );
    });
  });

  group('ChatAdapterBinding', () {
    test('defaults to NullChatAdapter', () {
      expect(ChatAdapterBinding.instance, isA<NullChatAdapter>());
    });

    test('bind then reset round-trips to the default', () {
      final fake = _FakeChatAdapter();
      ChatAdapterBinding.bind(fake);
      expect(ChatAdapterBinding.instance, same(fake));
      ChatAdapterBinding.reset();
      expect(ChatAdapterBinding.instance, isA<NullChatAdapter>());
    });
  });

  group('withScopeCeiling', () {
    test('prepends the scope-ceiling system message', () {
      final result = withScopeCeiling(const [
        ChatMessage(role: ChatRole.user, content: 'hi'),
      ]);
      expect(result, hasLength(2));
      expect(result.first.role, ChatRole.system);
      expect(result.first.content, nexChatScopeCeilingPrompt);
      expect(result.last.content, 'hi');
    });

    test(
      // Appends to a caller-provided system message rather than skipping it:
      // skipping meant the ceiling never reached the model at all on the app's
      // local path, which always supplies its own system prompt. Exactly one
      // system message is still the invariant — the ceiling joins it, it does
      // not become a second one.
      'the ceiling joins a caller-provided system message instead of being skipped',
      () {
        const existing = ChatMessage(
          role: ChatRole.system,
          content: 'custom system prompt',
        );
        final result = withScopeCeiling(const [
          existing,
          ChatMessage(role: ChatRole.user, content: 'hi'),
        ]);
        expect(result, hasLength(2));
        expect(result.first.role, ChatRole.system);
        expect(result.first.content, startsWith('custom system prompt'));
        expect(result.first.content, contains(nexChatScopeCeilingPrompt));
        // And it is idempotent: applying it again changes nothing.
        final again = withScopeCeiling(result);
        expect(again.first.content, result.first.content);
      },
    );
  });
}
