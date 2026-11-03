import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_ai/src/cloud/local_budget.dart';
import 'package:nex_core/nex_core.dart';

import 'fixtures/note_summary_samples.dart';

Note _note(String source) => Note(
  id: 'compression',
  deviceId: 'test',
  rev: 1,
  syncState: SyncState.pending,
  type: NoteType.text,
  content: source,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

http.Response _response(String text, {String finish = 'stop'}) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': text},
        'finish_reason': finish,
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  CloudAIAdapter adapter(
    List<Map<String, dynamic>> requests,
    Future<http.Response> Function(int call) reply,
  ) {
    final result = CloudAIAdapter(
      config: const AiProviderConfig(
        provider: AiProvider.openai,
        apiKey: 'test',
      ),
      outputLanguage: AiOutputLanguage.persian,
      client: MockClient((request) {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return reply(requests.length);
      }),
    );
    addTearDown(result.close);
    return result;
  }

  test(
    'multipart near-rewrite gets one compression attempt with full source',
    () async {
      final requests = <Map<String, dynamic>>[];
      final client = adapter(
        requests,
        (call) async => _response(
          call == 1
              ? '**مرتب‌شده**\n$multipartSummarySource'
              : compactMultipartSummary,
        ),
      );
      final result = await client.summarize(_note(multipartSummarySource));
      expect(result!.text, compactMultipartSummary.trim());
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(
          (request['messages'] as List).last['content'],
          multipartSummarySource.trim(),
        );
      }
      expect(
        (requests.last['messages'] as List).first['content'],
        contains('too close to a full rewrite'),
      );
      expect(
        requests.last['max_completion_tokens'],
        requests.first['max_completion_tokens'],
      );
      // Named topics, negation and a conditional final date are in the candidate.
      for (final topic in [
        'Refresh/Timeline',
        'sheen',
        'Untagged',
        'Paste',
        'recurring',
        'Caption',
        'Urgent',
        'Daily Nudge',
        '۲۰ آبان',
        'در غیر این صورت متوقف',
      ]) {
        expect(result.text, contains(topic));
      }
    },
  );

  test('a good multipart summary uses only one request', () async {
    final requests = <Map<String, dynamic>>[];
    final client = adapter(
      requests,
      (_) async => _response(compactMultipartSummary),
    );
    expect(
      (await client.summarize(_note(multipartSummarySource)))!.text,
      compactMultipartSummary.trim(),
    );
    expect(requests, hasLength(1));
  });

  test('English prose near-copy follows the same rule', () async {
    final source = List.filled(
      12,
      'The release remains conditional on fixing the scroll conflict and testing slow connections. '
      'Reversing the drag should close the refresh strip before the timeline starts moving. '
      'Cancelled refreshes must keep the previous text readable without a success effect.',
    ).join('\n\n');
    const compact =
        'Release only after fixing reverse-drag scrolling and testing slow connections; '
        'close the refresh strip first and keep previous text readable on cancellation.';
    final requests = <Map<String, dynamic>>[];
    final client = adapter(
      requests,
      (call) async => _response(call == 1 ? source : compact),
    );
    expect((await client.summarize(_note(source)))!.text, compact);
    expect(requests, hasLength(2));
  });

  test(
    'short dense notes are allowed to stay close to their source length',
    () async {
      const source =
          'طرح تأیید نشده؛ ۲۰ آبان فقط تاریخ هدف است. هزینه قطعی ۱۵۲ میلیون تومان؛ انتشار مشروط به آزمون است.';
      final requests = <Map<String, dynamic>>[];
      final client = adapter(requests, (_) async => _response(source));
      expect((await client.summarize(_note(source)))!.text, source);
      expect(requests, hasLength(1));
    },
  );

  test(
    'a long compact factual list does not cause a length-only retry',
    () async {
      final source = List.generate(
        80,
        (i) => 'مورد ${i + 100}: مسئول علی؛ وضعیت پیشنهادی؛ تاریخ قطعی نیست.',
      ).join('\n');
      final requests = <Map<String, dynamic>>[];
      final client = adapter(requests, (_) async => _response(source));
      expect((await client.summarize(_note(source)))!.text, source);
      expect(requests, hasLength(1));
    },
  );

  test('numeric records stay intact even in one long paragraph', () async {
    final source = List.generate(
      60,
      (i) =>
          'Batch ${i + 100}: quantity ${i + 200}, ceiling ${i + 300}, spent ${i + 400}.',
    ).join(' ');
    final requests = <Map<String, dynamic>>[];
    final client = adapter(requests, (_) async => _response(source));
    expect((await client.summarize(_note(source)))!.text, source);
    expect(requests, hasLength(1));
  });

  test('length alone does not penalise a different output language', () async {
    final source = List.filled(
      15,
      'This proposal is conditional and has not been approved. All final decisions must remain visible in the report.',
    ).join(' ');
    final reply = List.filled(
      15,
      'این پیشنهاد مشروط است و تأیید نشده است. تصمیم‌های نهایی باید در گزارش باقی بمانند.',
    ).join(' ');
    final requests = <Map<String, dynamic>>[];
    final client = adapter(requests, (_) async => _response(reply));
    expect((await client.summarize(_note(source)))!.text, reply);
    expect(requests, hasLength(1));
  });

  for (final failure in [
    'http',
    'timeout',
    'empty',
    'truncated',
    'number',
    'lost-number',
    'longer',
  ]) {
    test(
      'a $failure compression retry preserves the usable first result',
      () async {
        final requests = <Map<String, dynamic>>[];
        final client = adapter(requests, (call) async {
          if (call == 1) return _response(multipartSummarySource);
          return switch (failure) {
            'http' => http.Response('{"error":{"message":"busy"}}', 429),
            'timeout' => throw TimeoutException('test retry timeout'),
            'empty' => _response(''),
            'truncated' => _response(compactMultipartSummary, finish: 'length'),
            'number' => _response(
              compactMultipartSummary.replaceAll('۲۰ آبان', '۲۱ آبان'),
            ),
            'lost-number' => _response(
              compactMultipartSummary.replaceAll('۲۰ آبان', 'آبان'),
            ),
            _ => _response('$multipartSummarySource\nتوضیحات اضافه.'),
          };
        });
        expect(
          (await client.summarize(_note(multipartSummarySource)))!.text,
          multipartSummarySource.trim(),
        );
        expect(requests, hasLength(2));
        expect(client.lastReplyTruncated, isFalse);
        expect(client.lastFailureMessage, isNull);
      },
    );
  }

  test('numeric repair cannot start a third compression request', () async {
    final requests = <Map<String, dynamic>>[];
    final client = adapter(
      requests,
      (call) async => _response(
        call == 1
            ? multipartSummarySource.replaceAll('۲۰ آبان', '۲۱ آبان')
            : multipartSummarySource,
      ),
    );
    expect(
      (await client.summarize(_note(multipartSummarySource)))!.text,
      multipartSummarySource.trim(),
    );
    expect(requests, hasLength(2));
  });

  test('truncation repair cannot start a third compression request', () async {
    final requests = <Map<String, dynamic>>[];
    final client = adapter(
      requests,
      (call) async => _response(
        multipartSummarySource,
        finish: call == 1 ? 'length' : 'stop',
      ),
    );
    expect(
      (await client.summarize(_note(multipartSummarySource)))!.text,
      multipartSummarySource.trim(),
    );
    expect(requests, hasLength(2));
  });

  test(
    'local quality retry never clips the original to fit its longer prompt',
    () async {
      final model = _EchoModel();
      final client = CloudAIAdapter(
        config: const AiProviderConfig(),
        localModel: model,
      );
      addTearDown(client.close);
      // Learn the actual prompt budget rather than pinning prompt character counts.
      await client.summarize(_note('short note'));
      final prompt = model.histories.single.first.content;
      final room = LocalBudget.input - LocalBudget.estimate(prompt);
      final source = LocalBudget.clip(
        List.filled(
          50,
          'This deliberately expansive source repeats the same explanation about the release condition and preserving the full note. '
          'The release depends on the remaining work and should keep its qualifications instead of presenting the proposal as completed.',
        ).join('\n\n'),
        room - 5,
      );
      model.histories.clear();
      final result = await client.summarize(_note(source));
      expect(result!.text, source);
      expect(model.histories, hasLength(1));
      expect(model.histories.single.last.content, source);
      expect(client.lastReplyTruncated, isFalse);
    },
  );
}

class _EchoModel extends ChatAdapter {
  final histories = <List<ChatMessage>>[];
  @override
  bool get available => true;
  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) async {
    histories.add(history);
    return ChatResponse(content: history.last.content);
  }
}
