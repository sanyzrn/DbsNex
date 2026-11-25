import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';

/// The model is handed the app's own reading of the day, and told that it is
/// the reading that counts. This is the prompt half of the 2.9.0 rule; the
/// client half rejects an answer that contradicts it.
void main() {
  Future<String> systemPrompt({String ledger = ''}) async {
    final requests = <Map<String, dynamic>>[];
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(
        provider: AiProvider.openai,
        apiKey: 'test',
      ),
      client: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '📝 Call the bank at 11:20.'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(adapter.close);
    await adapter.digest(
      'today | text | Call the bank | DUE today 11:20',
      style: NexBriefStyle.blended,
      lines: 4,
      statusLedger: ledger,
    );
    return (requests.single['messages'] as List).first['content'] as String;
  }

  test('the status rule is in every brief prompt', () async {
    final system = await systemPrompt();
    expect(system, contains('computed by the app'));
    expect(system, contains('never call'));
    expect(system, contains('such an item done, missed, reminded, forgotten'));
    // No ledger, no placeholder heading left behind.
    expect(system, isNot(contains('FACTS COMPUTED BY THE APP')));
  });

  test('the ledger travels with the prompt, ahead of the answer', () async {
    final ledger =
        'FACTS COMPUTED BY THE APP at 10:30 (the model must respect these):\n'
        '- 2 due today, 0 overdue, 0 unfinished.';
    final system = await systemPrompt(ledger: ledger);
    expect(system, contains('FACTS COMPUTED BY THE APP at 10:30'));
    expect(system, contains('2 due today'));
    expect(
      system.indexOf('2 due today'),
      lessThan(system.indexOf('Answer with at most')),
    );
  });
}
