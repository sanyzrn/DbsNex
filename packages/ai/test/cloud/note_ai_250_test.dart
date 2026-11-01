import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  CloudAIAdapter adapter(
    String reply, {
    int status = 200,
    String finish = 'stop',
    void Function(Map<String, dynamic>)? sent,
  }) => CloudAIAdapter(
    config: const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
    client: MockClient((request) async {
      sent?.call(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': reply},
              'finish_reason': finish,
            },
          ],
        }),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  test(
    'summary prompt preserves decisions and scales beyond one sentence',
    () async {
      late Map<String, dynamic> body;
      final source = List.filled(
        100,
        'Decision 12: keep the final date 2026-11-01.',
      ).join('\n');
      final note = Note(
        id: 'n',
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
        type: NoteType.text,
        content: source,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final result = await adapter(
        'Decision one. Decision two.',
        sent: (value) => body = value,
      ).summarize(note)!;
      expect(result.text, 'Decision one. Decision two.');
      expect(body['max_completion_tokens'], greaterThan(200));
      final system = (body['messages'] as List).first['content'] as String;
      expect(system, contains('final decisions'));
      expect(system, contains('numbers'));
      expect(system, contains('do not force one sentence'));
    },
  );

  test(
    'summary affordance hides short notes; supports dense and unspaced text',
    () {
      expect(CloudAIAdapter.hasSummaryWorthwhileText('A short note.'), isFalse);
      expect(
        CloudAIAdapter.hasSummaryWorthwhileText(
          List.filled(100, 'word').join(' '),
        ),
        isTrue,
      );
      expect(
        CloudAIAdapter.hasSummaryWorthwhileText(List.filled(700, '漢').join()),
        isTrue,
      );
    },
  );

  test(
    'language detection returns real multilingual metadata or stays unknown',
    () async {
      expect(
        await adapter('["fa","ru","de"]').detectTranslationLanguages('source'),
        ['fa', 'ru', 'de'],
      );
      expect(
        await adapter('not JSON').detectTranslationLanguages('source'),
        isNull,
      );
    },
  );

  test('lossless split preserves blank lines, indentation, CRLF and emoji', () {
    final source =
        '  Heading\r\n\r\n- first\n  continuation\n\n\n'
        '${List.filled(600, 'متن😀漢字').join(' ')}\n\nTail  ';
    final chunks = NexTranslationChunk.split(source, limit: 101);
    expect(
      chunks.map((c) => '${c.prefix}${c.text}${c.separator}').join(),
      source,
    );
    expect(chunks.every((c) => c.text.length <= 101), isTrue);
    for (final chunk in chunks) {
      expect(utf8.decode(utf8.encode(chunk.text)), chunk.text);
    }
  });

  test('valid long Chinese output and source markup are kept', () async {
    final reply = List.filled(60, '这是正确的中文翻译').join();
    expect(
      await adapter(reply).translateChunk(
        'source',
        target: NexTranslationLanguage.fromCode('zh')!,
      ),
      reply,
    );
    const markup = '# Heading\n- <think>literal source</think>\n- 42';
    expect(
      await adapter(
        markup,
      ).translateChunk(markup, target: NexTranslationLanguage.values[1]),
      markup,
    );
  });

  test(
    'an incomplete translation is never accepted as a completed chunk',
    () async {
      final client = adapter('partial', finish: 'length');
      expect(
        await client.translateChunk(
          'source',
          target: NexTranslationLanguage.values[1],
        ),
        isNull,
      );
      expect(client.lastFailureKind, AiFailureKind.incomplete);
    },
  );

  for (final (status, kind) in [
    (429, AiFailureKind.rateLimit),
    (413, AiFailureKind.tooLarge),
    (415, AiFailureKind.unsupported),
    (401, AiFailureKind.credentials),
    (503, AiFailureKind.unavailable),
  ]) {
    test('image HTTP $status carries a factual category', () async {
      final client = adapter('', status: status);
      await expectLater(
        client.ocr(ImageRef(mediaUri: 'image.jpg', bytes: Uint8List(2))),
        throwsA(
          isA<AiUnavailableException>().having((e) => e.kind, 'kind', kind),
        ),
      );
    });
  }

  test('missing and oversized files fail before upload', () async {
    var calls = 0;
    final client = adapter('unused', sent: (_) => calls++);
    await expectLater(
      client.ocr(const ImageRef(mediaUri: '/missing/nex-image.jpg')),
      throwsA(
        isA<AiUnavailableException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.missingFile,
        ),
      ),
    );
    await expectLater(
      client.ocr(
        ImageRef(mediaUri: 'image.jpg', bytes: Uint8List(15 * 1024 * 1024 + 1)),
      ),
      throwsA(
        isA<AiUnavailableException>().having(
          (e) => e.kind,
          'kind',
          AiFailureKind.tooLarge,
        ),
      ),
    );
    expect(calls, 0);
  });

  test(
    'transport timeout is distinguished from no recognizable image content',
    () async {
      final client = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'test',
        ),
        client: MockClient((_) async => throw TimeoutException('deadline')),
      );
      await expectLater(
        client.ocr(ImageRef(mediaUri: 'image.jpg', bytes: Uint8List(2))),
        throwsA(
          isA<AiUnavailableException>().having(
            (e) => e.kind,
            'kind',
            AiFailureKind.timeout,
          ),
        ),
      );
      expect(
        (await adapter(
          'NO_TEXT',
        ).ocr(ImageRef(mediaUri: 'image.jpg', bytes: Uint8List(2)))!).text,
        isEmpty,
      );
      await expectLater(
        adapter('').ocr(ImageRef(mediaUri: 'image.jpg', bytes: Uint8List(2))),
        throwsA(isA<AiUnavailableException>()),
      );
    },
  );
  test(
    'Gemini distinguishes no intelligible speech from truncated audio output',
    () async {
      CloudAIAdapter audio(String text, String finish) => CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'test',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': text},
                    ],
                  },
                  'finishReason': finish,
                },
              ],
            }),
            200,
          ),
        ),
      );
      final source = AudioRef(mediaUri: 'voice.m4a', bytes: Uint8List(2));
      expect(
        (await audio('NO_SPEECH', 'STOP').transcribe(source)!).text,
        isEmpty,
      );
      await expectLater(
        audio('partial transcript', 'MAX_TOKENS').transcribe(source),
        throwsA(
          isA<AiUnavailableException>().having(
            (e) => e.kind,
            'kind',
            AiFailureKind.incomplete,
          ),
        ),
      );
    },
  );
}
