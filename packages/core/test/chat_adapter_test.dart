import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

class _FakeChatAdapter implements ChatAdapter {
  List<ChatMessage>? lastHistory;

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
      'does not stack a second system message on top of a caller-provided one',
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
        expect(result.first.content, 'custom system prompt');
      },
    );
  });
}
