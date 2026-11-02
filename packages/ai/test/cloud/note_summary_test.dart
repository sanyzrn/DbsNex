import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';

Note note(String text) => Note(
  id: 'summary-test',
  deviceId: 'test',
  rev: 1,
  syncState: SyncState.pending,
  type: NoteType.text,
  content: text,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  CloudAIAdapter client(
    List<({String text, String finish})> replies,
    List<Map<String, dynamic>> requests,
  ) => CloudAIAdapter(
    config: const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
    outputLanguage: AiOutputLanguage.persian,
    client: MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      final reply = replies[requests.length - 1];
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': reply.text},
              'finish_reason': reply.finish,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  test(
    'full long source, including final conditions, reaches the model',
    () async {
      final source = [
        'شروع: دوره آزمایشی، بدون درآمد واقعی.',
        ...List.filled(
          100,
          'گزارش‌های مشتریان هنوز علت قطعی را نشان نمی‌دهند.',
        ),
        'پایان: انتشار مشروط به رفع خطا و آزمون اینترنت ضعیف است. '
            'سقف بودجه ۱۸ میلیون؛ هزینه واقعی ۷٫۲ میلیون تومان.',
      ].join('\n\n');
      final requests = <Map<String, dynamic>>[];
      final adapter = client([
        (
          text: 'انتشار مشروط به رفع خطا و آزمون اینترنت ضعیف است.',
          finish: 'stop',
        ),
      ], requests);
      addTearDown(adapter.close);
      await adapter.summarize(note(source));
      final messages = requests.single['messages'] as List;
      expect(messages.last['content'], source);
      final system = messages.first['content'] as String;
      expect(system, contains('including its final sections'));
      expect(system, contains('budget ceiling is not spending'));
      expect(system, contains('privacy restrictions'));
      expect(system, contains('not approved does not mean rejected'));
      expect(system, contains('what happens if a condition is unmet'));
      expect(system, contains('about half'));
      expect(system, contains('do not calculate new values'));
    },
  );

  test(
    'digit scripts and numeric separators do not trigger a repair',
    () async {
      final requests = <Map<String, dynamic>>[];
      const reply =
          '۳۲۰۰ نسخه، هر نسخه ۴۷٬۵۰۰ تومان؛ کل ۱۵۲ میلیون. '
          'پیشنهاد ۱۶۶٫۴ میلیون تأیید نشده است. تاریخ هدف 2026-11-12.';
      final adapter = client([(text: reply, finish: 'stop')], requests);
      addTearDown(adapter.close);
      final result = await adapter.summarize(
        note(
          '3200 copies at 47,500 Toman; total 152 million. '
          '166.4 million is an unapproved proposal. Target ۲۰۲۶-۱۱-۱۲.',
        ),
      );
      expect(result!.text, reply);
      expect(requests, hasLength(1));
    },
  );

  test(
    'a changed quantity gets one repair with the unchanged source',
    () async {
      final requests = <Map<String, dynamic>>[];
      const source = 'تعداد ۳۲۰۰ نسخه است؛ مبلغ قطعی چاپ ۱۵۲ میلیون تومان است.';
      final adapter = client([
        (text: '۳۳۰۰ نسخه؛ ۱۵۲ میلیون تومان.', finish: 'stop'),
        (text: '۳۲۰۰ نسخه؛ ۱۵۲ میلیون تومان.', finish: 'stop'),
      ], requests);
      addTearDown(adapter.close);
      final result = await adapter.summarize(note(source));
      expect(result!.text, '۳۲۰۰ نسخه؛ ۱۵۲ میلیون تومان.');
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect((request['messages'] as List).last['content'], source);
      }
      expect(
        (requests.last['messages'] as List).first['content'],
        contains('unsupported numeric values: 3300'),
      );
    },
  );

  test('a repeated numeric error is refused, with no third request', () async {
    final requests = <Map<String, dynamic>>[];
    final adapter = client([
      (text: '۳۳۰۰ نسخه', finish: 'stop'),
      (text: '٣٣٠٠ نسخه', finish: 'stop'),
    ], requests);
    addTearDown(adapter.close);
    expect(
      (await adapter.summarize(note('۳۲۰۰ نسخه چاپ شود.')))!.text,
      isEmpty,
    );
    expect(requests, hasLength(2));
    expect(adapter.lastFailureMessage, contains('changed numeric values'));
  });

  test('does not accept newly calculated financial figures', () async {
    final requests = <Map<String, dynamic>>[];
    final adapter = client([
      (text: 'Remaining budget: 1540 dollars.', finish: 'stop'),
      (text: 'Remaining budget: 1540 dollars.', finish: 'stop'),
    ], requests);
    addTearDown(adapter.close);
    final result = await adapter.summarize(
      note(
        'Budget ceiling: \$2,400. Actual spending: \$860. '
        'Remaining budget is not an approved purchase order.',
      ),
    );
    expect(result!.text, isEmpty);
  });

  test(
    'a refused numeric reply leaves the saved summary and source intact',
    () async {
      final db = NexDatabase.openInMemory();
      addTearDown(db.close);
      final repo = SqliteNoteRepository(db, localDeviceId: 'test');
      const source = '۳۲۰۰ نسخه چاپ شود؛ مبلغ قطعی چاپ ۱۵۲ میلیون تومان است.';
      final saved = repo.insert(note(source));
      repo.setSummaryText(saved.id, 'خلاصه قبلی معتبر است.');
      final requests = <Map<String, dynamic>>[];
      final adapter = client([
        (text: '۳۳۰۰ نسخه چاپ شود.', finish: 'stop'),
        (text: '۳۳۰۰ نسخه چاپ شود.', finish: 'stop'),
      ], requests);
      addTearDown(adapter.close);
      final service = EnrichmentService(
        repo: repo,
        adapter: adapter,
        capabilities: const AiCapabilities(summarization: true),
      );
      expect(await service.summarizeOnDemand(saved.id), isNull);
      expect(repo.getById(saved.id)!.summaryText, 'خلاصه قبلی معتبر است.');
      expect(repo.getById(saved.id)!.content, source);
      expect(requests, hasLength(2));
    },
  );

  test('truncated generation gets one larger, complete attempt', () async {
    final requests = <Map<String, dynamic>>[];
    final adapter = client([
      (text: 'Partial answer', finish: 'length'),
      (text: 'Complete answer with the release condition.', finish: 'stop'),
    ], requests);
    addTearDown(adapter.close);
    final result = await adapter.summarize(
      note('Source with release condition.'),
    );
    expect(result!.text, 'Complete answer with the release condition.');
    expect(requests, hasLength(2));
    expect(
      requests.last['max_completion_tokens'],
      greaterThan(requests.first['max_completion_tokens'] as int),
    );
  });

  test('a second truncated answer is not accepted', () async {
    final requests = <Map<String, dynamic>>[];
    final adapter = client([
      (text: 'Partial', finish: 'length'),
      (text: 'Still partial', finish: 'length'),
    ], requests);
    addTearDown(adapter.close);
    expect((await adapter.summarize(note('Original note.')))!.text, isEmpty);
    expect(adapter.lastReplyTruncated, isTrue);
    expect(requests, hasLength(2));
  });

  test('list ordinals in either script are not treated as facts', () async {
    final requests = <Map<String, dynamic>>[];
    const reply = '۱. طرح تصویب نشده.\n2. زمان انتشار نامشخص است.';
    final adapter = client([(text: reply, finish: 'stop')], requests);
    addTearDown(adapter.close);
    expect(
      (await adapter.summarize(note('طرح پیشنهادی است. زمان نداریم.')))!.text,
      reply,
    );
    expect(requests, hasLength(1));
  });

  test(
    'bookmark descriptions retain their separate one-sentence contract',
    () async {
      final requests = <Map<String, dynamic>>[];
      final adapter = client([
        (text: 'Page description.', finish: 'stop'),
      ], requests);
      addTearDown(adapter.close);
      expect(
        await adapter.summarizeText('A page excerpt.'),
        'Page description.',
      );
      expect(requests.single['max_completion_tokens'], 200);
      expect(
        (requests.single['messages'] as List).first['content'],
        contains('one sentence'),
      );
    },
  );
}
