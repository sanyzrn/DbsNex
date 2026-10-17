import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

String reply(String text, {String? finish}) => jsonEncode({
  'choices': [
    {
      'message': {'content': text},
      if (finish != null) 'finish_reason': finish,
    },
  ],
});
void main() {
  for (final provider in [
    AiProvider.openai,
    AiProvider.gemini,
    AiProvider.anthropic,
  ]) {
    test('$provider refuses known truncated text', () async {
      final body = switch (provider) {
        AiProvider.gemini => {
          'candidates': [
            {
              'finishReason': 'MAX_TOKENS',
              'content': {
                'parts': [
                  {'text': 'partial'},
                ],
              },
            },
          ],
        },
        AiProvider.anthropic => {
          'stop_reason': 'max_tokens',
          'content': [
            {'type': 'text', 'text': 'partial'},
          ],
        },
        _ => jsonDecode(reply('partial', finish: 'length')),
      };
      final adapter = CloudAIAdapter(
        config: AiProviderConfig(provider: provider, apiKey: 'k'),
        client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
      );
      expect(
        await adapter.translate(
          'Original complete text',
          target: AiOutputLanguage.persian,
        ),
        isNull,
      );
      expect(adapter.lastReplyTruncated, isTrue);
      expect(
        await adapter.rewrite(
          'Original complete text',
          style: NexRewriteStyle.values.first,
        ),
        isNull,
      );
      adapter.close();
    });
  }
  test(
    'rewrite preserves authored markup and still strips actual reasoning on normal text',
    () async {
      var answer = '<analysis>literal source</analysis> tail';
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((_) async => http.Response(reply(answer), 200)),
      );
      expect(
        await adapter.rewrite(answer, style: NexRewriteStyle.values.first),
        answer,
      );
      answer = '<think>private reasoning</think> Clean answer';
      expect(
        await adapter.rewrite(
          'Normal source',
          style: NexRewriteStyle.values.first,
        ),
        'Clean answer',
      );
      expect(
        adapter.extractTextForTest(
          reply('Before <analysis>literal</analysis> after'),
        ),
        'Before <analysis>literal</analysis> after',
      );
    },
  );
  test(
    'cloud history is bounded without mutating or clipping the newest question',
    () async {
      late List<dynamic> sent;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((r) async {
          sent = (jsonDecode(r.body) as Map)['messages'] as List;
          return http.Response(reply('ok'), 200);
        }),
      );
      final history = [
        for (var i = 0; i < 121; i++)
          ChatMessage(
            role: i.isEven ? ChatRole.user : ChatRole.assistant,
            content: 'turn $i',
          ),
      ];
      await adapter.chat(history);
      expect(sent.length, lessThanOrEqualTo(61));
      expect(sent.last['content'], 'turn 120');
      expect(history.length, 121);
      expect(
        await adapter.chat([
          ChatMessage(role: ChatRole.user, content: 'x' * 100000),
        ]),
        isNull,
      );
      expect(adapter.lastFailureStatus, 413);
    },
  );
  test(
    'Stop aborts a live IO request and the same adapter can answer again',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<void>();
      var calls = 0;
      server.listen((request) async {
        await request.drain<void>();
        if (++calls == 1) {
          received.complete();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(reply('retry works'));
        await request.response.close();
      });
      final adapter = CloudAIAdapter(
        config: AiProviderConfig(
          provider: AiProvider.custom,
          apiKey: 'k',
          baseUrl: 'http://127.0.0.1:${server.port}',
          model: 'test',
        ),
      );
      try {
        final pending = adapter.chat([
          const ChatMessage(role: ChatRole.user, content: 'hello'),
        ]);
        final check = expectLater(
          pending,
          throwsA(isA<http.RequestAbortedException>()),
        );
        await received.future;
        adapter.cancelChat();
        await check;
        expect(
          await adapter.chat([
            const ChatMessage(role: ChatRole.user, content: 'again'),
          ]),
          'retry works',
        );
      } finally {
        adapter.close();
        await server.close(force: true);
      }
    },
  );
}
