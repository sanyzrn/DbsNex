import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';

void main() {
  for (final style in [
    NexBriefStyle.assistant,
    NexBriefStyle.blended,
    NexBriefStyle.planner,
    NexBriefStyle.custom,
  ]) {
    test(
      '$style prioritises attention while preserving user-directed custom reports',
      () async {
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
                    'message': {'content': '📝 Review the release decision.'},
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
        const source =
            'today | text | Release decision is waiting.\ntoday | HABIT | {"name":"Water","doneToday":true,"dailyGoal":8}';
        await adapter.digest(
          source,
          includesHabits: true,
          style: style,
          instruction: 'Report all completed habits',
          lines: 4,
        );
        expect(requests, hasLength(1));
        final messages = requests.single['messages'] as List;
        expect(messages.last['content'], source);
        final system = messages.first['content'] as String;
        expect(system, contains('Never call a completed goal unfinished'));
        if (style == NexBriefStyle.custom) {
          expect(system, contains('Report all completed habits'));
          expect(system, contains('Follow the custom instruction'));
          expect(
            system,
            isNot(contains('Normally omit routine completed daily goals')),
          );
        } else {
          expect(
            system,
            contains(
              'Prioritise overdue reminders, unfinished work, important decisions and upcoming events',
            ),
          );
          expect(system, contains('at most one short combined sentence'));
          expect(
            system,
            contains('Never give several completed habits separate lines'),
          );
        }
      },
    );
  }
}
