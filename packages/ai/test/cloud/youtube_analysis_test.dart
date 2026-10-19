import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';

/// 2.1.7: a YouTube link in a note can be analysed by a provider that
/// watches video from its address.
void main() {
  CloudAIAdapter gemini(void Function(http.Request) seen) => CloudAIAdapter(
    config: const AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k'),
    client: MockClient((request) async {
      seen(request);
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'A talk about gardens.\n- 0:30 soil\n- 2:10 water'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        }),
        200,
      );
    }),
  );

  test(
    'Gemini is handed the canonical watch address before the words',
    () async {
      late http.Request request;
      final adapter = gemini((r) => request = r);
      expect(adapter.canWatchYouTube, isTrue);
      final reply = await adapter.analyzeYouTubeVideo(
        'https://youtu.be/dQw4w9WgXcQ?si=tracking',
        title: 'Gardens',
      );
      expect(reply, contains('- 0:30 soil'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final parts =
          ((body['contents'] as List).single as Map)['parts'] as List<dynamic>;
      // 2.1.9: half the frames, at low resolution — a fifth of the tokens,
      // so a long talk fits in what a free plan allows in a minute.
      expect(parts.first, {
        'file_data': {
          'file_uri': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        },
        'video_metadata': {'fps': CloudAIAdapter.videoFps},
      });
      expect(
        (body['generationConfig'] as Map)['mediaResolution'],
        'MEDIA_RESOLUTION_LOW',
      );
      expect((parts.last as Map)['text'], contains('Gardens'));
      final system = jsonEncode(body['systemInstruction']);
      expect(system, contains('Only what is in the video'));
      // No token ceiling: a thinking model would spend it before writing.
      expect((body['generationConfig'] as Map?)?['maxOutputTokens'], isNull);
    },
  );

  test(
    'not a video, or a provider that cannot watch one, asks nothing',
    () async {
      var requests = 0;
      final adapter = gemini((_) => requests++);
      expect(
        await adapter.analyzeYouTubeVideo('https://www.youtube.com/@channel'),
        isNull,
      );
      final openai = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'k',
        ),
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      expect(openai.canWatchYouTube, isFalse);
      expect(
        await openai.analyzeYouTubeVideo(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        isNull,
      );
      expect(requests, 0);
    },
  );

  test(
    'a model that refuses the low-resolution settings is asked plainly',
    (() async {
      final bodies = <Map<String, dynamic>>[];
      final adapter = CloudAIAdapter(
        config: const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'k',
        ),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if ((body['generationConfig'] as Map).containsKey(
            'mediaResolution',
          )) {
            return http.Response(
              jsonEncode({
                'error': {
                  'message':
                      'Invalid JSON payload received. Unknown name '
                      '"mediaResolution" at \'generation_config\'',
                },
              }),
              400,
            );
          }
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'A talk.'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            }),
            200,
          );
        }),
      );
      expect(
        await adapter.analyzeYouTubeVideo('https://youtu.be/dQw4w9WgXcQ'),
        'A talk.',
      );
      expect(bodies, hasLength(2));
      final plain = (bodies.last['contents'] as List).single as Map;
      expect((plain['parts'] as List).first, {
        'file_data': {
          'file_uri': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        },
      });
    }),
  );

  test('a refusal keeps the provider\'s reason for the person', () async {
    var requests = 0;
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k'),
      client: MockClient((_) async {
        requests++;
        return http.Response(
          jsonEncode({
            'error': {
              'message': 'Resource has been exhausted (e.g. check quota).',
            },
          }),
          429,
        );
      }),
    );
    expect(
      await adapter.analyzeYouTubeVideo('https://youtu.be/dQw4w9WgXcQ'),
      isNull,
    );
    // A limit is not a refusal of the settings: asked once, not twice.
    expect(requests, 1);
    expect(adapter.lastFailureStatus, 429);
    expect(adapter.lastFailureMessage, contains('exhausted'));
  });
}
