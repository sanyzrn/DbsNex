import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  Note textNote(String content) {
    final now = DateTime.now().toUtc();
    return Note(
      id: 'n1',
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  group('AiProviderConfig', () {
    test('falls back to the provider defaults', () {
      const config = AiProviderConfig(
        provider: AiProvider.openai,
        apiKey: 'k',
      );
      expect(config.resolvedBaseUrl, 'https://api.openai.com');
      expect(config.resolvedModel, 'gpt-4o-mini');
      expect(config.isUsable, isTrue);
    });

    test('a trailing slash on the base URL never doubles up in a path', () {
      const config = AiProviderConfig(
        provider: AiProvider.custom,
        apiKey: 'k',
        baseUrl: 'https://example.invalid/',
        model: 'm',
      );
      expect(config.resolvedBaseUrl, 'https://example.invalid');
    });

    test('custom needs a base URL and a model of its own', () {
      const config = AiProviderConfig(provider: AiProvider.custom, apiKey: 'k');
      expect(config.isUsable, isFalse);
    });

    test('no key means unusable, whatever else is set', () {
      const config = AiProviderConfig(provider: AiProvider.anthropic);
      expect(config.isUsable, isFalse);
    });

    test('wire names round-trip, and an unknown one is not a crash', () {
      for (final provider in AiProvider.values) {
        expect(AiProviderWire.fromWire(provider.wireName), provider);
      }
      expect(AiProviderWire.fromWire('some-future-vendor'), AiProvider.none);
      expect(AiProviderWire.fromWire(null), AiProvider.none);
    });
  });

  group('CloudAIAdapter request shape', () {
    test('Anthropic gets its own endpoint, headers and body', () async {
      late http.Request seen;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.anthropic,
          apiKey: 'secret',
        ),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Work, Ideas'},
              ],
            }),
            200,
          );
        }),
      );

      final tags = await adapter.suggestTags(textNote('a note'))!;

      expect(seen.url.path, '/v1/messages');
      expect(seen.headers['x-api-key'], 'secret');
      expect(seen.headers.containsKey('anthropic-version'), isTrue);
      expect(seen.headers.containsKey('authorization'), isFalse);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      // Anthropic takes the system prompt as a field, not a message.
      expect(body['system'], isNotNull);
      expect((body['messages'] as List).length, 1);
      expect(tags.map((t) => t.name), ['Work', 'Ideas']);
    });

    test('OpenAI-shaped providers get chat/completions and a bearer', () async {
      late http.Request seen;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openrouter,
          apiKey: 'secret',
        ),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'a short summary'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final summary = await adapter.summarize(textNote('a long note'))!;

      expect(seen.url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
      expect(seen.headers['authorization'], 'Bearer secret');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect((body['messages'] as List).length, 2);
      expect(summary.text, 'a short summary');
    });

    test('an unusable config asks for nothing at all', () {
      var called = false;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(provider: AiProvider.openai),
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      // Null is this contract's "unavailable", and it must not cost a request.
      expect(adapter.suggestTags(textNote('x')), isNull);
      expect(adapter.summarize(textNote('x')), isNull);
      expect(adapter.embed('x'), isNull);
      expect(called, isFalse);
    });

    test('Anthropic offers no embeddings rather than guessing an endpoint', () {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.anthropic,
          apiKey: 'k',
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(adapter.embed('x'), isNull);
    });

    test('a capability a provider lacks is unavailable, not guessed at', () {
      // Only Gemini and OpenAI can hear audio. Claiming otherwise would send a
      // recording somewhere that cannot read it and store whatever came back.
      for (final provider in AiProvider.values) {
        final adapter = CloudAIAdapter(
          config: AiProviderConfig(provider: provider, apiKey: 'k'),
          client: MockClient((_) async => http.Response('{}', 200)),
        );
        final call = adapter.transcribe(
          const AudioRef(mediaUri: '/tmp/does-not-exist.m4a'),
        );
        if (provider.hearsAudio) {
          // Available in principle; null here only because the file is absent.
          expect(call, isNull, reason: '${provider.wireName}: no such file');
        } else {
          expect(call, isNull, reason: provider.wireName);
        }
      }
      expect(AiProvider.gemini.hearsAudio, isTrue);
      expect(AiProvider.openai.hearsAudio, isTrue);
      expect(AiProvider.anthropic.hearsAudio, isFalse);
      expect(AiProvider.openrouter.hearsAudio, isFalse);
      expect(AiProvider.none.hearsAudio, isFalse);
    });

    test('a media note with no derived text is not sent anywhere', () {
      var called = false;
      final now = DateTime.now().toUtc();
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      final photo = Note(
        id: 'p1',
        type: NoteType.photo,
        mediaUri: '/tmp/p.jpg',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      );
      expect(adapter.suggestTags(photo), isNull);
      expect(called, isFalse);
    });
  });

  group('Gemini', () {
    test('uses its own endpoint, header and body — not OpenAI\'s', () async {
      late http.Request seen;
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'google-key',
        ),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Work, Ideas'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final tags = await adapter.suggestTags(textNote('a note'))!;

      // The exact three things that made a Google key fail under "Custom":
      // the path, the auth header, and the request body.
      expect(
        seen.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.0-flash:generateContent?key=google-key',
      );
      // The key rides in the query string, the way Google's own quickstarts
      // send it. No auth header of any kind: a request that authenticates two
      // ways is a request with two ways to be wrong.
      expect(seen.headers.containsKey('authorization'), isFalse);
      expect(seen.headers.containsKey('x-goog-api-key'), isFalse);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['systemInstruction'], isNotNull);
      expect(body['contents'], isA<List<dynamic>>());
      expect(tags.map((t) => t.name), ['Work', 'Ideas']);
    });

    test('a reply split across parts is joined, not truncated', () {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final text = adapter.extractTextForTest(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'first half '},
                  {'text': 'second half'},
                ],
              },
            },
          ],
        }),
      );
      expect(text, 'first half second half');
    });

    test('a blocked or empty candidate list is null, not an empty answer', () {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        adapter.extractTextForTest(jsonEncode({'candidates': <Object>[]})),
        isNull,
      );
      expect(adapter.extractTextForTest('{}'), isNull);
    });
  });

  group('a failed test says what actually went wrong', () {
    Future<AiTestResult> testWith(int status, String body) {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
          model: 'gemini-9-nonexistent',
        ),
        client: MockClient((_) async => http.Response(body, status)),
      );
      return adapter.test();
    }

    test('a rejected key is reported as a rejected key', () async {
      // Every one of these used to come back as the same sentence — "the
      // provider rejected the request" — so a wrong key, a retired model and a
      // rate limit were indistinguishable from a typo in the model name.
      final result = await testWith(
        400,
        jsonEncode({
          'error': {'message': 'API key not valid. Please pass a valid API key.'},
        }),
      );
      expect(result.success, isFalse);
      expect(result.detail, contains('API key not valid'));
    });

    test('a missing model is reported as a missing model', () async {
      final result = await testWith(
        404,
        jsonEncode({
          'error': {'message': 'models/gemini-9-nonexistent is not found'},
        }),
      );
      expect(result.detail, contains('404'));
      expect(result.detail, contains('is not found'));
    });

    test('a rate limit is not dressed up as a bad key', () async {
      final result = await testWith(429, '{}');
      expect(result.detail, contains('429'));
    });

    test('a non-JSON error page is passed through, bounded', () async {
      final result = await testWith(502, '<html>Bad Gateway</html>');
      expect(result.detail, contains('502'));
      expect(result.detail, contains('Bad Gateway'));
    });

    test('a 200 carrying no text is not blamed on the provider', () async {
      // A reasoning model that spends its whole budget thinking answers 200
      // with no parts. That is a different problem from a refusal and has to
      // read as one.
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ),
        client: MockClient((_) async => http.Response('{"candidates":[]}', 200)),
      );
      final result = await adapter.test();
      expect(result.success, isFalse);
      expect(result.detail, contains('no text'));
    });
  });

  group('connection test', () {
    test('names what is missing before touching the network', () async {
      var called = false;
      MockClient watcher() => MockClient((_) async {
            called = true;
            return http.Response('{}', 200);
          });

      expect(
        (await CloudAIAdapter(
          config: const AiProviderConfig(),
          client: watcher(),
        ).test())
            .detail,
        contains('provider'),
      );
      expect(
        (await CloudAIAdapter(
          config: const AiProviderConfig(provider: AiProvider.openai),
          client: watcher(),
        ).test())
            .detail,
        contains('key'),
      );
      expect(called, isFalse);
    });

    test('a rejected key fails with something actionable', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'wrong',
        ),
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );
      final result = await adapter.test();
      expect(result.success, isFalse);
      expect(result.detail, contains('key'));
    });

    test('a working provider reports the model it reached', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'right',
          model: 'gpt-4o',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'ok'},
                },
              ],
            }),
            200,
          ),
        ),
      );
      final result = await adapter.test();
      expect(result.success, isTrue);
      expect(result.detail, 'gpt-4o');
    });

    test('a network failure is reported, not thrown at the UI', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((_) async => throw const SocketishFailure()),
      );
      final result = await adapter.test();
      expect(result.success, isFalse);
      expect(result.detail, isNotEmpty);
    });
  });
}

/// Stands in for whatever the socket layer throws when there is no network.
class SocketishFailure implements Exception {
  const SocketishFailure();

  @override
  String toString() => 'no route to host';
}
