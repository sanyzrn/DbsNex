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
      expect(AiProviderWire.fromWire('gemini'), AiProvider.none);
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

    test('transcription and OCR report unavailable on every provider', () {
      for (final provider in AiProvider.values) {
        final adapter = CloudAIAdapter(
          config: AiProviderConfig(provider: provider, apiKey: 'k'),
          client: MockClient((_) async => http.Response('{}', 200)),
        );
        expect(
          adapter.transcribe(const AudioRef(mediaUri: '/tmp/a.m4a')),
          isNull,
          reason: provider.wireName,
        );
        expect(
          adapter.ocr(const ImageRef(mediaUri: '/tmp/a.jpg')),
          isNull,
          reason: provider.wireName,
        );
      }
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
