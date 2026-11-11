import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  test(
    'empty search requests aggregate metadata, malformed commands are detected',
    () {
      final action = parseAssistantAction('{"action":"search","query":""}')!;
      expect(action.kind, AssistantActionKind.search);
      expect(action.text, isNull);
      expect(action.isRead, isTrue);
      expect(
        hasInvalidAssistantAction('{"action":"search","query":""}'),
        isFalse,
      );
      expect(hasInvalidAssistantAction('Sure {"action":"search"}'), isTrue);
      expect(
        hasInvalidAssistantAction('```nex\n{"action":"search"}\n```'),
        isTrue,
      );
      expect(hasInvalidAssistantAction('{"action":"search",'), isTrue);
      expect(hasInvalidAssistantAction('```json\n{"example":1}\n```'), isFalse);
    },
  );

  for (final provider in [
    AiProvider.openai,
    AiProvider.gemini,
    AiProvider.anthropic,
  ]) {
    test(
      '$provider retries truncated chat once with a bounded larger budget',
      () async {
        final budgets = <int>[];
        var alwaysTruncated = false;
        final adapter = CloudAIAdapter(
          config: AiProviderConfig(provider: provider, apiKey: 'k'),
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map;
            budgets.add(
              (body['max_completion_tokens'] ??
                      body['max_tokens'] ??
                      (body['generationConfig'] as Map?)?['maxOutputTokens'])
                  as int,
            );
            final truncated = alwaysTruncated || budgets.length == 1;
            final response = switch (provider) {
              AiProvider.gemini => {
                'candidates': [
                  {
                    'finishReason': truncated ? 'MAX_TOKENS' : 'STOP',
                    'content': {
                      'parts': [
                        {'text': 'answer'},
                      ],
                    },
                  },
                ],
              },
              AiProvider.anthropic => {
                'stop_reason': truncated ? 'max_tokens' : 'end_turn',
                'content': [
                  {'type': 'text', 'text': 'answer'},
                ],
              },
              _ => {
                'choices': [
                  {
                    'finish_reason': truncated ? 'length' : 'stop',
                    'message': {'content': 'answer'},
                  },
                ],
              },
            };
            return http.Response(jsonEncode(response), 200);
          }),
        );
        addTearDown(adapter.close);
        const turns = [
          ChatMessage(role: ChatRole.user, content: 'How many notes?'),
        ];
        const options = AiChatOptions(length: AiAnswerLength.brief);
        expect(await adapter.chat(turns, options: options), 'answer');
        expect(budgets, [1024, 2048]);
        expect(adapter.lastReplyTruncated, isFalse);
        budgets.clear();
        alwaysTruncated = true;
        expect(await adapter.chat(turns, options: options), isNull);
        expect(budgets, [1024, 2048]);
        expect(adapter.lastReplyTruncated, isTrue);
      },
    );
  }
}
