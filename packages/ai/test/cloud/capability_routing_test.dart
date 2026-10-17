import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  test('OpenRouter additions require explicit opt-in', () {
    const config = AiProviderConfig(
      provider: AiProvider.openrouter,
      apiKey: 'key',
    );
    expect(config.supportsTranscription, isFalse);
    expect(config.supportsEmbeddings, isFalse);
    expect(
      config.copyWith(audio: AiCapabilityMode.enabled).supportsTranscription,
      isTrue,
    );
    expect(
      config.copyWith(embeddings: AiCapabilityMode.enabled).supportsEmbeddings,
      isTrue,
    );
  });

  test(
    'router multipart audio uses a transcription slug, not the chat model',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://openrouter.ai/api/v1/audio/transcriptions',
        );
        expect(request.headers['authorization'], 'Bearer key');
        expect(request.body, contains('openai/whisper-large-v3'));
        expect(request.body, isNot(contains('openrouter/free')));
        return http.Response('{"text":"spoken words"}', 200);
      });
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openrouter,
          apiKey: 'key',
          model: 'openrouter/free',
          audio: AiCapabilityMode.enabled,
        ),
        client: client,
      );
      expect(
        (await adapter.transcribe(
          AudioRef(mediaUri: 'voice.m4a', bytes: Uint8List.fromList([1, 2])),
        ))?.text,
        'spoken words',
      );
    },
  );

  test(
    'router embeddings use the embeddings endpoint and model namespace',
    () async {
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openrouter,
          apiKey: 'key',
          embeddings: AiCapabilityMode.enabled,
        ),
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://openrouter.ai/api/v1/embeddings',
          );
          expect(
            jsonDecode(request.body)['model'],
            'openai/text-embedding-3-small',
          );
          return http.Response('{"data":[{"embedding":[0.1,0.2]}]}', 200);
        }),
      );
      expect((await adapter.embed('words'))?.dimensions, 2);
    },
  );

  test(
    'custom independent routes/models round-trip and isolate vector spaces',
    () {
      const config = AiProviderConfig(
        provider: AiProvider.custom,
        apiKey: 'key',
        baseUrl: 'https://example.com/chat',
        model: 'chat-model',
        transcriptionUrl: 'https://example.com/speech',
        transcriptionModel: 'speech-model',
        embeddingUrl: 'https://example.com/vectors',
        embeddingModelId: 'vectors-model',
        embeddings: AiCapabilityMode.enabled,
        images: AiCapabilityMode.disabled,
      );
      final restored = AiProviderConfig.fromMap(config.toMap());
      expect(restored.toMap(), config.toMap());
      expect(restored.supportsTranscription, isTrue);
      expect(restored.supportsImages, isFalse);
      expect(
        restored.embeddingSpace,
        isNot(
          config
              .copyWith(embeddingUrl: 'https://example.com/other')
              .embeddingSpace,
        ),
      );
      expect(
        restored.embeddingSpace,
        isNot(config.copyWith(embeddingModelId: 'other').embeddingSpace),
      );
      expect(
        restored.copyWith(model: 'other-chat').embeddingSpace,
        restored.embeddingSpace,
      );
    },
  );

  test('Gemini speech model is independent of the chat model', () async {
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(
        provider: AiProvider.gemini,
        apiKey: 'key',
        model: 'chat-model',
        transcriptionModel: 'speech-model',
      ),
      client: MockClient((request) async {
        expect(request.url.path, '/v1beta/models/speech-model:generateContent');
        return http.Response(
          '{"candidates":[{"content":{"parts":[{"text":"heard"}]}}]}',
          200,
        );
      }),
    );
    expect(
      (await adapter.transcribe(
        AudioRef(mediaUri: 'voice.m4a', bytes: Uint8List(1)),
      ))?.text,
      'heard',
    );
  });

  test('disabled images never upload image bytes', () {
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(
        provider: AiProvider.openai,
        apiKey: 'key',
        images: AiCapabilityMode.disabled,
      ),
      client: MockClient((_) async => throw StateError('must not upload')),
    );
    expect(
      adapter.ocr(ImageRef(mediaUri: 'photo.jpg', bytes: Uint8List(1))),
      isNull,
    );
  });
}
