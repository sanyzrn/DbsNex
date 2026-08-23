import 'package:nex_ai/nex_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaceholderLocalChatAdapter', () {
    test('sendMessage returns the placeholder response', () async {
      const adapter = PlaceholderLocalChatAdapter();
      final call = adapter.sendMessage(const [
        ChatMessage(role: ChatRole.user, content: 'hello'),
      ]);
      expect(call, isNotNull);
      final response = await call!;
      expect(response.content, contains("isn't wired up yet"));
      expect(response.refusedOutOfScope, isFalse);
    });
  });
}
