import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';

/// 2.1.7: the written half of the profile's portrait.
void main() {
  test('asks for a reflection, not an assessment, and reads the JSON', () async {
    late Map<String, dynamic> body;
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"headline": "A quiet planner", "portrait": "You plan.",'
                      ' "traits": [{"name": "Planning", "score": 80, "line": "a"},'
                      ' {"name": "Care", "score": 70, "line": "b"},'
                      ' {"name": "Curiosity", "score": 60, "line": "c"}],'
                      ' "strengths": ["lists"], "invitation": "Rest."}',
                },
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
        );
      }),
    );
    final portrait = await adapter.writePortrait(
      'today | text | plan the week',
      facts: 'notes: 40',
      basedOn: 40,
    );
    expect(portrait?.headline, 'A quiet planner');
    expect(portrait?.basedOn, 40);
    final prompt = jsonEncode(body['messages']);
    expect(prompt, contains('not an assessment'));
    expect(prompt, contains('Never use psychology labels'));
    expect(prompt, contains('Never repeat private details'));
    expect(prompt, contains('plan the week'));
  });

  test('nothing to read from asks nothing', () async {
    var requests = 0;
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    expect(await adapter.writePortrait(' ', facts: '', basedOn: 0), isNull);
    expect(requests, 0);
  });
}
