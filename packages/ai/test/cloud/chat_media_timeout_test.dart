import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  for (final provider in [
    AiProvider.openai,
    AiProvider.gemini,
    AiProvider.anthropic,
  ]) {
    testWidgets(
      '$provider image chat keeps its media deadline; plain chat stays at 90s',
      (tester) async {
        final pending = <Completer<http.Response>>[];
        final adapter = CloudAIAdapter(
          config: AiProviderConfig(provider: provider, apiKey: 'test'),
          client: MockClient((_) {
            final response = Completer<http.Response>();
            pending.add(response);
            return response.future;
          }),
        );
        const question = ChatMessage(
          role: ChatRole.user,
          content: 'Describe this',
        );
        Object? plainError;
        Object? imageError;
        unawaited(
          adapter.chat(const [question]).catchError((Object error) {
            plainError = error;
            return null;
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 91));
        expect(plainError, isA<TimeoutException>());
        unawaited(
          adapter
              .chat(
                const [question],
                options: const AiChatOptions(
                  attachments: [
                    NexChatAttachment(bytes: [1, 2, 3], mimeType: 'image/png'),
                  ],
                ),
              )
              .catchError((Object error) {
                imageError = error;
                return null;
              }),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 91));
        expect(imageError, isNull);
        await tester.pump(const Duration(seconds: 90));
        expect(imageError, isA<TimeoutException>());
        for (final response in pending) {
          response.complete(http.Response(jsonEncode({}), 200));
        }
        await tester.pump();
      },
    );
  }
}
