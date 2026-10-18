import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  const history = [ChatMessage(role: ChatRole.user, content: 'hello')];

  test('native OpenAI takes max_completion_tokens; reasoning models drop the '
      'temperature', () async {
    for (final (model, reasoning) in [
      ('gpt-4o-mini', false),
      ('gpt-4.1', false),
      ('o3', true),
      ('gpt-5-mini', true),
      ('gpt-5.1', true),
      ('gpt-6.1-sol', true),
    ]) {
      final bodies = <Map<String, dynamic>>[];
      final adapter = CloudAIAdapter(
        config: AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
          model: model,
        ),
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'ok'},
                  'finish_reason': 'stop',
                },
              ],
            }),
            200,
          );
        }),
      );
      expect((await adapter.test()).success, isTrue, reason: model);
      expect(await adapter.chat(history), 'ok', reason: model);
      for (final body in bodies) {
        expect(body.containsKey('max_completion_tokens'), isTrue);
        expect(body.containsKey('max_tokens'), isFalse, reason: model);
      }
      expect(bodies.last.containsKey('temperature'), !reasoning, reason: model);
    }
  });

  test('only native OpenAI changes its request parameter policy', () async {
    for (final provider in [
      AiProvider.openai,
      AiProvider.custom,
      AiProvider.openrouter,
    ]) {
      final bodies = <Map<String, dynamic>>[];
      final adapter = CloudAIAdapter(
        config: AiProviderConfig(
          provider: provider,
          apiKey: 'k',
          model: 'o3',
          baseUrl: provider == AiProvider.custom
              ? 'https://gateway.example/v1/chat/completions'
              : '',
        ),
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'ok'},
                },
              ],
            }),
            200,
          );
        }),
      );
      expect((await adapter.test()).success, isTrue);
      expect(await adapter.chat(history), 'ok');
      for (final body in bodies) {
        expect(
          body.containsKey('max_completion_tokens'),
          provider == AiProvider.openai,
        );
        expect(body.containsKey('max_tokens'), provider != AiProvider.openai);
      }
      expect(
        bodies.last.containsKey('temperature'),
        provider != AiProvider.openai,
      );
    }
  });

  test('the next chat request uses the current output language', () async {
    var language = AiOutputLanguage.english;
    final prompts = <String>[];
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
      outputLanguageProvider: () => language,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        prompts.add(
          ((body['messages'] as List).first as Map)['content'] as String,
        );
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
          200,
        );
      }),
    );
    await adapter.chat(history);
    language = AiOutputLanguage.persian;
    await adapter.chat(history);
    expect(prompts.first, startsWith(AiOutputLanguage.english.leadRule));
    expect(prompts.last, startsWith(AiOutputLanguage.persian.leadRule));
  });

  test(
    'audio errors preserve status and do not become empty transcripts',
    () async {
      for (final status in [401, 404, 429, 500]) {
        final adapter = CloudAIAdapter(
          config: const AiProviderConfig(
            provider: AiProvider.openai,
            apiKey: 'k',
          ),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {'message': 'provider detail'},
              }),
              status,
            ),
          ),
        );
        await expectLater(
          adapter.transcribe(
            AudioRef(mediaUri: 'a.m4a', bytes: Uint8List.fromList([1])),
          )!,
          throwsA(isA<AiUnavailableException>()),
        );
        expect(adapter.lastFailureStatus, status);
      }
      for (final body in ['not JSON', '{}']) {
        final adapter = CloudAIAdapter(
          config: const AiProviderConfig(
            provider: AiProvider.openai,
            apiKey: 'k',
          ),
          client: MockClient((_) async => http.Response(body, 200)),
        );
        await expectLater(
          adapter.transcribe(
            AudioRef(mediaUri: 'a.m4a', bytes: Uint8List.fromList([1])),
          )!,
          throwsA(isA<AiUnavailableException>()),
        );
      }
    },
  );

  testWidgets(
    'audio deadline includes a stalled body and cancels its subscription',
    (tester) async {
      final stream = StreamController<List<int>>();
      final client = _StreamingClient(stream.stream);
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: client,
        mediaTimeout: const Duration(seconds: 3),
      );
      Object? error;
      unawaited(
        adapter
            .transcribe(
              AudioRef(mediaUri: 'a.m4a', bytes: Uint8List.fromList([1])),
            )!
            .then<void>(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(error, isA<TimeoutException>());
      expect(stream.hasListener, isFalse);
      expect(client.closed, isFalse, reason: 'an injected client is borrowed');
      unawaited(stream.close());
    },
  );

  test('retiring a client waits for its in-flight response body', () async {
    final inner = _StreamingClient(Stream.value([1, 2]));
    final client = DisclosureClient(inner, provider: 'test');
    final response = await client.send(
      http.Request('GET', Uri.https('example.test')),
    );
    client.retire();
    expect(inner.closed, isFalse);
    await expectLater(
      client.send(http.Request('GET', Uri.https('example.test'))),
      throwsA(isA<http.ClientException>()),
    );
    await response.stream.drain<void>();
    expect(inner.closed, isTrue);
  });

  test('Gemini audio is recorded as audio rather than an image', () async {
    final dir = Directory.systemTemp.createTempSync('nex_audio_log_');
    NexDisclosureLog.configure(dir.path);
    try {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'hello'},
                    ],
                  },
                },
              ],
            }),
            200,
          ),
        ),
      );
      await adapter.transcribe(
        AudioRef(mediaUri: 'a.m4a', bytes: Uint8List.fromList([1])),
      )!;
      final entries = await NexDisclosureLog.read();
      expect(entries.single.content, contains(DisclosureContent.audio));
      expect(entries.single.content, isNot(contains(DisclosureContent.image)));
    } finally {
      NexDisclosureLog.configure('${dir.path}/removed');
      dir.deleteSync(recursive: true);
    }
  });
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.body);
  final Stream<List<int>> body;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body, 200);
  @override
  void close() {
    closed = true;
  }
}
