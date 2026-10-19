import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';

/// 2.1.8: what a model can do is found by asking it, once, when its
/// connection is tested — not chosen by hand from three dropdowns.
void main() {
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  http.Response geminiText(String text) => json({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
        'finishReason': 'STOP',
      },
    ],
  });
  http.Response openAiText(String text) => json({
    'choices': [
      {
        'message': {'content': text},
        'finish_reason': 'stop',
      },
    ],
  });
  http.Response error(int status, String message) => json({
    'error': {'message': message},
  }, status);

  final at = DateTime.utc(2026, 10, 19, 9);

  group('Gemini', () {
    const gemini = AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k');

    test('all four found working, each from its own request', () async {
      final seen = <String>[];
      final heard = <AiCapability>[];
      final check = await nexCheckCapabilities(
        gemini,
        clock: () => at,
        onResult: (capability, _) => heard.add(capability),
        client: MockClient((request) async {
          final body = request.body;
          if (request.url.path.endsWith(':embedContent')) {
            seen.add('embeddings');
            return json({
              'embedding': {
                'values': [0.1, 0.2],
              },
            });
          }
          if (body.contains('"file_uri"')) {
            seen.add('video');
            expect(body, contains(nexCheckVideo));
            return geminiText('Elephants');
          }
          if (body.contains('"audio/wav"')) {
            seen.add('audio');
            return geminiText('A steady tone.');
          }
          if (body.contains('"image/png"')) {
            seen.add('images');
            return geminiText('47');
          }
          fail('unexpected request: $body');
        }),
      );
      expect(seen.toSet(), {'images', 'audio', 'embeddings', 'video'});
      expect(heard.toSet(), AiCapability.values.toSet());
      for (final capability in AiCapability.values) {
        expect(
          check.results[capability]!.verdict,
          AiProbeVerdict.works,
          reason: '$capability',
        );
      }
      final applied = check.applyTo(gemini);
      expect(applied.images, AiCapabilityMode.enabled);
      expect(applied.audio, AiCapabilityMode.enabled);
      expect(applied.embeddings, AiCapabilityMode.enabled);
      expect(applied.video, AiCapabilityMode.enabled);
      expect(applied.checkedTime, at);
      expect(applied.supportsVideo, isTrue);
      expect(CloudAIAdapter.watchesYouTube(applied), isTrue);
    });

    test('a model that cannot hear or watch is told apart from one that '
        'is busy', () async {
      final check = await nexCheckCapabilities(
        gemini,
        clock: () => at,
        client: MockClient((request) async {
          final body = request.body;
          if (request.url.path.endsWith(':embedContent')) {
            return error(429, 'Resource has been exhausted');
          }
          if (body.contains('"file_uri"')) {
            return error(400, 'Video input is not supported for this model.');
          }
          if (body.contains('"audio/wav"')) {
            return error(400, 'Audio input modality is not enabled.');
          }
          // An answer in Persian digits is still the picture read.
          return geminiText('۴۷');
        }),
      );
      expect(check.results[AiCapability.images]!.works, isTrue);
      final audio = check.results[AiCapability.audio]!;
      expect(audio.verdict, AiProbeVerdict.refused);
      expect(audio.status, 400);
      expect(audio.detail, contains('Audio input'));
      expect(
        check.results[AiCapability.video]!.verdict,
        AiProbeVerdict.refused,
      );
      final embeddings = check.results[AiCapability.embeddings]!;
      expect(embeddings.verdict, AiProbeVerdict.unknown);
      expect(embeddings.status, 429);

      final applied = check.applyTo(gemini);
      expect(applied.supportsTranscription, isFalse);
      expect(applied.supportsVideo, isFalse);
      expect(CloudAIAdapter.watchesYouTube(applied), isFalse);
      // Not known, so the provider's default still stands.
      expect(applied.embeddings, AiCapabilityMode.automatic);
      expect(applied.supportsEmbeddings, isTrue);
    });

    test('the audio check uses the speech model, not the chat model', () async {
      final config = gemini.copyWith(
        model: 'gemini-chat',
        transcriptionModel: 'gemini-ears',
      );
      final urls = <String>[];
      await nexCheckCapabilities(
        config,
        client: MockClient((request) async {
          if (request.body.contains('"audio/wav"')) {
            urls.add(request.url.path);
          }
          return geminiText('ok');
        }),
      );
      expect(urls, ['/v1beta/models/gemini-ears:generateContent']);
    });
  });

  group('OpenAI-shaped', () {
    const openai = AiProviderConfig(provider: AiProvider.openai, apiKey: 'k');

    test('a reply without the number is a model that did not see', () async {
      final check = await nexCheckCapabilities(
        openai,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/audio/transcriptions')) {
            expect(request.headers['content-type'], contains('multipart'));
            return error(404, 'The model `whisper-1` does not exist');
          }
          if (request.url.path.endsWith('/embeddings')) {
            return json({
              'data': [
                {
                  'embedding': [0.3, 0.4],
                },
              ],
            });
          }
          expect(request.body, contains('data:image/png;base64,'));
          return openAiText('I cannot see any picture. 1 + 1 = 2.');
        }),
      );
      expect(
        check.results[AiCapability.images]!.verdict,
        AiProbeVerdict.refused,
      );
      expect(
        check.results[AiCapability.audio]!.verdict,
        AiProbeVerdict.refused,
      );
      expect(check.results[AiCapability.embeddings]!.works, isTrue);
      // Only Gemini fetches a video by its address; nothing is asked.
      expect(check.results[AiCapability.video]!.verdict, AiProbeVerdict.absent);
      final applied = check.applyTo(openai);
      expect(applied.supportsImages, isFalse);
      expect(applied.supportsTranscription, isFalse);
      expect(applied.supportsEmbeddings, isTrue);
    });

    test('a 200 without a transcript or vector is a refusal', () async {
      final check = await nexCheckCapabilities(
        const AiProviderConfig(
          provider: AiProvider.custom,
          apiKey: 'k',
          baseUrl: 'https://gw.example/v1/chat/completions',
          model: 'm',
        ),
        client: MockClient((request) async {
          if (request.url.path == '/v1/audio/transcriptions') {
            return json({'status': 'ok'});
          }
          if (request.url.path == '/v1/embeddings') {
            return http.Response('<html>not here</html>', 200);
          }
          return openAiText('47');
        }),
      );
      expect(check.results[AiCapability.images]!.works, isTrue);
      expect(
        check.results[AiCapability.audio]!.verdict,
        AiProbeVerdict.refused,
      );
      expect(
        check.results[AiCapability.embeddings]!.verdict,
        AiProbeVerdict.refused,
      );
    });

    test('OpenRouter: speech and search found by asking, not by default', () {
      const before = AiProviderConfig(
        provider: AiProvider.openrouter,
        apiKey: 'k',
      );
      expect(before.supportsEmbeddings, isFalse);
      final after = AiCapabilityCheck(
        at: at,
        results: const {
          AiCapability.images: AiProbeResult(AiProbeVerdict.works),
          AiCapability.audio: AiProbeResult(AiProbeVerdict.refused),
          AiCapability.embeddings: AiProbeResult(AiProbeVerdict.works),
          AiCapability.video: AiProbeResult(AiProbeVerdict.absent),
        },
      ).applyTo(before);
      expect(after.supportsEmbeddings, isTrue);
      // Search would start indexing old notes on its own: the client asks.
      expect(nexNewlyOffered(before, after), {AiCapability.embeddings});
      // A first setup is not an upgrade; the consent covers it.
      expect(nexNewlyOffered(const AiProviderConfig(), after), isEmpty);
    });
  });

  test('Anthropic: no speech or search service, so nothing is asked', () async {
    final paths = <String>[];
    final check = await nexCheckCapabilities(
      const AiProviderConfig(provider: AiProvider.anthropic, apiKey: 'k'),
      client: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.body, contains('"media_type":"image/png"'));
        // Within what every Claude model accepts.
        expect(jsonDecode(request.body)['max_tokens'], 1024);
        return json({
          'content': [
            {'type': 'text', 'text': 'The number is 47.'},
          ],
          'stop_reason': 'end_turn',
        });
      }),
    );
    expect(paths, ['/v1/messages']);
    expect(check.results[AiCapability.images]!.works, isTrue);
    expect(check.results[AiCapability.audio]!.verdict, AiProbeVerdict.absent);
    expect(
      check.results[AiCapability.embeddings]!.verdict,
      AiProbeVerdict.absent,
    );
    expect(check.results[AiCapability.video]!.verdict, AiProbeVerdict.absent);
  });

  test('no network and too slow are not known, not refused', () async {
    final check = await nexCheckCapabilities(
      const AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k'),
      limit: const Duration(milliseconds: 200),
      client: MockClient((request) async {
        if (request.body.contains('"image/png"')) {
          throw const SocketException('Network is unreachable');
        }
        if (request.body.contains('"file_uri"')) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        throw http.ClientException('Connection reset');
      }),
    );
    for (final capability in AiCapability.values) {
      expect(
        check.results[capability]!.verdict,
        AiProbeVerdict.unknown,
        reason: '$capability',
      );
    }
  });

  group('what a check leaves behind', () {
    const gemini = AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k');
    final found = AiCapabilityCheck(
      at: at,
      results: const {
        AiCapability.images: AiProbeResult(AiProbeVerdict.works),
        AiCapability.audio: AiProbeResult(AiProbeVerdict.refused),
        AiCapability.embeddings: AiProbeResult(AiProbeVerdict.works),
        AiCapability.video: AiProbeResult(AiProbeVerdict.refused),
      },
    );

    test('survives being stored', () {
      final stored = AiProviderConfig.fromMap(found.applyTo(gemini).toMap());
      expect(stored.checkedTime, at);
      expect(stored.supportsTranscription, isFalse);
      expect(stored.supportsVideo, isFalse);
    });

    test('says nothing about another model', () {
      final changed = found.applyTo(gemini).copyWith(model: 'gemini-other');
      expect(changed.checkedTime, isNull);
      // The provider's defaults stand in until the next check.
      expect(changed.supportsTranscription, isTrue);
      expect(changed.supportsVideo, isTrue);
    });

    test('a busy re-check keeps what the last one found', () {
      final first = found.applyTo(gemini);
      final busy = AiCapabilityCheck(
        at: at.add(const Duration(days: 1)),
        results: const {
          AiCapability.images: AiProbeResult(AiProbeVerdict.unknown),
          AiCapability.audio: AiProbeResult(AiProbeVerdict.unknown),
          AiCapability.embeddings: AiProbeResult(AiProbeVerdict.unknown),
          AiCapability.video: AiProbeResult(AiProbeVerdict.unknown),
        },
      ).applyTo(first);
      expect(busy.audio, AiCapabilityMode.disabled);
      expect(busy.video, AiCapabilityMode.disabled);
      expect(busy.checkedTime, at.add(const Duration(days: 1)));
    });

    test('a choice made by hand before 2.1.8 holds until the first check', () {
      final legacy = gemini.copyWith(audio: AiCapabilityMode.disabled);
      expect(legacy.checkedFor, isEmpty);
      expect(legacy.supportsTranscription, isFalse);
    });
  });

  test('the test files are what they say they are', () {
    final picture = nexCheckPicture();
    expect(picture.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(ascii.decode(picture.sublist(12, 16)), 'IHDR');
    final tone = nexCheckTone();
    expect(ascii.decode(tone.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(tone.sublist(8, 12)), 'WAVE');
    // One second of 16 kHz 16-bit mono, and its header.
    expect(tone.length, 44 + 32000);
    expect(nexLatinDigits('۴۷ و ٤٧'), '47 و 47');
  });

  test('no check without a usable configuration', () async {
    final check = await nexCheckCapabilities(
      const AiProviderConfig(provider: AiProvider.gemini),
      client: MockClient((_) async => fail('nothing should be sent')),
    );
    expect(check.results, isEmpty);
  });

  test('a rejected embedding keeps the provider\'s reason', () async {
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
      client: MockClient((_) async => error(403, 'Project lacks access')),
    );
    await expectLater(adapter.embed('x'), throwsA(isA<Exception>()));
    expect(adapter.lastFailureStatus, 403);
  });

  group('the provider\'s own model list', () {
    test('Gemini: chat models only, without the "models/" prefix', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ),
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.headers['x-goog-api-key'], 'k');
          return json({
            'models': [
              {
                'name': 'models/gemini-flash-latest',
                'supportedGenerationMethods': ['generateContent'],
              },
              {
                'name': 'models/gemini-embedding-001',
                'supportedGenerationMethods': ['embedContent'],
              },
              {
                'name': 'models/gemini-2.5-flash-preview-tts',
                'supportedGenerationMethods': ['generateContent'],
              },
              {
                'name': 'models/gemma-3-27b-it',
                'supportedGenerationMethods': ['generateContent'],
              },
            ],
          });
        }),
      );
      expect(await adapter.listModels(), [
        'gemini-flash-latest',
        'gemma-3-27b-it',
      ]);
    });

    test('OpenAI: speech, image and embedding models are left out', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://api.openai.com/v1/models');
          return json({
            'data': [
              {'id': 'gpt-5-mini'},
              {'id': 'text-embedding-3-small'},
              {'id': 'whisper-1'},
              {'id': 'gpt-4o-mini'},
              {'id': 'dall-e-3'},
            ],
          });
        }),
      );
      expect(await adapter.listModels(), ['gpt-4o-mini', 'gpt-5-mini']);
    });

    test('Custom: the models route beside the chat route', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.custom,
          apiKey: 'k',
          baseUrl: 'https://gw.example/openai/v1/chat/completions',
        ),
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://gw.example/openai/v1/models');
          return json({
            'data': [
              {'id': 'local/llama'},
            ],
          });
        }),
      );
      expect(await adapter.listModels(), ['local/llama']);
    });

    test('a refusal says why', () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.anthropic,
          apiKey: 'k',
        ),
        client: MockClient((_) async => error(401, 'invalid x-api-key')),
      );
      await expectLater(
        adapter.listModels(),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('invalid x-api-key'),
          ),
        ),
      );
    });
  });

  group('Gemini through a gateway', () {
    test('its address works with or without the version on the end', () {
      for (final typed in [
        'https://gw.example',
        'https://gw.example/',
        'https://gw.example/v1beta',
        'https://gw.example/v1beta/',
        'https://gw.example/v1beta/models',
      ]) {
        final config = AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
          baseUrl: typed,
        );
        expect(config.resolvedBaseUrl, 'https://gw.example', reason: typed);
        expect(config.gatewayHost, 'gw.example');
        expect(
          config.embeddingEndpoint,
          'https://gw.example/v1beta/models/gemini-embedding-001:embedContent',
        );
      }
      // A path in front of the version is kept.
      expect(
        const AiProviderConfig(
          provider: AiProvider.gemini,
          baseUrl: 'https://gw.example/google/v1beta',
        ).resolvedBaseUrl,
        'https://gw.example/google',
      );
      const google = AiProviderConfig(provider: AiProvider.gemini);
      expect(google.gatewayHost, isNull);
      expect(
        google.resolvedBaseUrl,
        'https://generativelanguage.googleapis.com',
      );
    });

    test('every request goes to it, in Gemini\'s own shape', () async {
      const config = AiProviderConfig(
        provider: AiProvider.gemini,
        apiKey: 'reseller-key',
        baseUrl: 'https://gw.example/v1beta',
      );
      final hosts = <String>{};
      final check = await nexCheckCapabilities(
        config,
        client: MockClient((request) async {
          hosts.add(request.url.host);
          expect(request.headers['x-goog-api-key'], 'reseller-key');
          expect(request.url.path, startsWith('/v1beta/models/'));
          if (request.url.path.endsWith(':embedContent')) {
            return json({
              'embedding': {
                'values': [0.1],
              },
            });
          }
          if (request.body.contains('"file_uri"')) {
            expect(request.body, contains(nexCheckVideo));
            return geminiText('Elephants.');
          }
          return geminiText(
            request.body.contains('"image/png"') ? '47' : 'A beep.',
          );
        }),
      );
      expect(hosts, {'gw.example'});
      expect(check.results.values.every((r) => r.works), isTrue);
      expect(CloudAIAdapter.watchesYouTube(check.applyTo(config)), isTrue);
    });

    test('a gateway that drops the video is not taken at its word', () async {
      final check = await nexCheckCapabilities(
        const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
          baseUrl: 'https://gw.example/v1beta',
        ),
        client: MockClient((request) async {
          if (request.body.contains('"file_uri"')) {
            // The words arrived, the video did not.
            return geminiText('I do not see any video attached.');
          }
          if (request.url.path.endsWith(':embedContent')) {
            return json({
              'embedding': {
                'values': [0.1],
              },
            });
          }
          return geminiText('47');
        }),
      );
      final video = check.results[AiCapability.video]!;
      expect(video.verdict, AiProbeVerdict.refused);
      expect(video.detail, contains('do not see'));
    });

    test('a different gateway is a different configuration', () {
      const google = AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k');
      final gateway = google.copyWith(baseUrl: 'https://gw.example/v1beta');
      expect(
        gateway.capabilityFingerprint,
        isNot(google.capabilityFingerprint),
      );
      // Vectors from one are not compared with the other's.
      expect(gateway.embeddingSpace, isNot(google.embeddingSpace));
    });
  });
}
