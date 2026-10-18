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
      expect(parts.first, {
        'file_data': {
          'file_uri': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        },
      });
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
}
