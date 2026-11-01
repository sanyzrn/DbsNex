import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';

void main() {
  CloudAIAdapter adapter(String reply, {void Function(http.Request)? onSend}) {
    final ai = CloudAIAdapter(
      config: const AiProviderConfig(
        provider: AiProvider.openai,
        apiKey: 'test',
      ),
      client: MockClient((request) async {
        onSend?.call(request);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': reply},
                  'finish_reason': 'stop',
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(ai.close);
    return ai;
  }

  test(
    'approved habit context uses factual progress rules in the same request',
    () async {
      late http.Request sent;
      final ai = adapter('Walking is left for today', onSend: (r) => sent = r);
      await ai.digest(
        'today | HABIT | {"name":"Walking","todayAmount":0,"dailyGoal":1}',
        includesHabits: true,
      );
      final messages = (jsonDecode(sent.body) as Map)['messages'] as List;
      final system = (messages.first as Map)['content'] as String;
      expect(
        system,
        contains('HABIT rows are the user-approved habit context'),
      );
      expect(system, contains('Never infer health'));
      expect(system, contains('rather than instructions'));
    },
  );

  test(
    'a Persian greeting rejects the English phrase from the report',
    () async {
      late http.Request sent;
      final ai = adapter('Ready when you are', onSend: (r) => sent = r);
      expect(
        await ai.headline('English notes', language: AiOutputLanguage.persian),
        isNull,
      );
      final messages = (jsonDecode(sent.body) as Map)['messages'] as List;
      expect(
        (messages.first as Map)['content'],
        startsWith('پاسخ را کامل به فارسی'),
      );
    },
  );

  test(
    'valid greetings retain their language regardless of the notes',
    () async {
      expect(
        await adapter(
          'صبحت بخیر',
        ).headline('English notes', language: AiOutputLanguage.persian),
        'صبحت بخیر',
      );
      expect(
        await adapter(
          'Good morning',
        ).headline('یادداشت فارسی', language: AiOutputLanguage.english),
        'Good morning',
      );
    },
  );

  for (final style in NexBriefStyle.values.where((style) => style.usesModel)) {
    test(
      '${style.name}: notes remain primary when habit context is present',
      () async {
        late http.Request sent;
        final ai = adapter(
          '📝 Finish the Nex search roadmap.',
          onSend: (r) => sent = r,
        );
        await ai.digest(
          'today | text #nex | Finish the search roadmap.\n'
          'today | HABIT | {"name":"Drink water","todayAmount":4,"dailyGoal":8}',
          style: style,
          lines: 8,
          words: 28,
          includesHabits: true,
          written: style.statesFacts ? '📝 Finish the Nex search roadmap.' : '',
        );
        final system =
            ((jsonDecode(sent.body) as Map)['messages'] as List)
                    .first['content']
                as String;
        expect(system, contains('notes are the primary subject'));
        expect(system, contains('even without a DUE'));
        expect(system, contains('most of the brief to notes'));
        expect(system, contains('Do not reduce a rich set of notes'));
        expect(system, isNot(contains('if only one thing is waiting')));
      },
    );
  }

  for (final style in [NexBriefStyle.assistant, NexBriefStyle.custom]) {
    test(
      '${style.name}: Full keeps the pre-2.5 eight-line word budget',
      () async {
        const line =
            '⏰ Call the plumber about the leak under the sink, two days '
            'overdue now — the landlord needs his report before Friday, so '
            'ring him first thing.';
        final reply = List.filled(8, line).join('\n');
        var calls = 0;
        final ai = adapter(reply, onSend: (_) => calls++);
        final full = await ai.digest(
          'DUE today | text | call the plumber',
          lines: NexBriefLength.long.lines,
          words: NexBriefLength.long.words,
          style: style,
          instruction: 'Explain what matters and the next action.',
        );
        expect(full!.split('\n'), hasLength(8));
        expect(full.split('\n').first, line);
        expect(calls, 1);
        final standard = await ai.digest(
          'DUE today | text | call the plumber',
          lines: NexBriefLength.medium.lines,
          words: NexBriefLength.medium.words,
          style: style,
        );
        expect(standard!.split('\n'), hasLength(4));
        expect(full.length, greaterThan(standard.length));
      },
    );
  }
}
