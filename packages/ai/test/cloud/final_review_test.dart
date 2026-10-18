import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

String response(AiProvider provider, String? reason) =>
    jsonEncode(switch (provider) {
      AiProvider.anthropic => {
        if (reason != null) 'stop_reason': reason,
        'content': [
          {'type': 'text', 'text': 'Partial answer'},
        ],
      },
      AiProvider.gemini => {
        'candidates': [
          {
            if (reason != null) 'finishReason': reason,
            'content': {
              'parts': [
                {'text': 'Partial answer'},
              ],
            },
          },
        ],
      },
      _ => {
        'choices': [
          {
            if (reason != null) 'finish_reason': reason,
            'message': {'content': 'Partial answer'},
          },
        ],
      },
    });

void main() {
  for (final (provider, reason) in [
    (AiProvider.openai, 'content_filter'),
    (AiProvider.openai, 'tool_calls'),
    (AiProvider.anthropic, 'pause_turn'),
    (AiProvider.anthropic, 'model_context_window_exceeded'),
    (AiProvider.gemini, 'SAFETY'),
    (AiProvider.gemini, 'RECITATION'),
    (AiProvider.gemini, 'CONTINUATION'),
  ]) {
    test(
      '$provider $reason cannot become a replacement translation or rewrite',
      () async {
        final adapter = CloudAIAdapter(
          config: AiProviderConfig(provider: provider, apiKey: 'test'),
          client: MockClient(
            (_) async => http.Response(response(provider, reason), 200),
          ),
        );
        addTearDown(adapter.close);
        expect(
          await adapter.translate(
            'Original complete text',
            target: AiOutputLanguage.persian,
          ),
          isNull,
        );
        expect(
          await adapter.rewrite(
            'Original complete text',
            style: NexRewriteStyle.values.first,
          ),
          isNull,
        );
      },
    );
  }
  for (final (provider, reason) in [
    (AiProvider.openai, 'stop'),
    (AiProvider.anthropic, 'end_turn'),
    (AiProvider.anthropic, 'stop_sequence'),
    (AiProvider.gemini, 'STOP'),
    (AiProvider.custom, null),
  ]) {
    test('$provider accepts a complete or legacy gateway response', () async {
      final adapter = CloudAIAdapter(
        config: AiProviderConfig(provider: provider, apiKey: 'test'),
      );
      addTearDown(adapter.close);
      expect(
        adapter.extractTextForTest(response(provider, reason)),
        'Partial answer',
      );
    });
  }
  test(
    'a truncated Gemini transcript cannot replace an earlier complete reading',
    () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'test',
        ),
        client: MockClient(
          (_) async =>
              http.Response(response(AiProvider.gemini, 'MAX_TOKENS'), 200),
        ),
      );
      addTearDown(adapter.close);
      await expectLater(
        adapter.transcribe(
          AudioRef(mediaUri: 'voice.m4a', bytes: Uint8List.fromList([1, 2])),
        ),
        throwsA(isA<AiUnavailableException>()),
      );
      expect(adapter.lastReplyTruncated, isTrue);
    },
  );
}
