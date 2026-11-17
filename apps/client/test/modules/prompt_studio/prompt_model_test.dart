import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/prompt_studio/prompt_model.dart';

void main() {
  test('slots support Persian and deduplicate in first-appearance order', () {
    final t = PromptTemplate('{{موضوع}} {{role}} {{موضوع}} {{ role }}');
    expect(t.slots, ['موضوع', 'role']);
    expect(t.fill({'موضوع': 'نکس', 'role': 'editor'}), 'نکس editor نکس editor');
  });
  test(
    'JSON, markdown, single braces, malformed and triple braces stay literal',
    () {
      final t = PromptTemplate(
        '{"key": "value"} [label](url) {topic} {{{role}}} {{bad:slot}}',
      );
      expect(t.slots, isEmpty);
      expect(t.fill({'key': 'wrong'}), t.body);
    },
  );
  test('replacement is literal and not recursive', () {
    final t = PromptTemplate('{{first}} / {{second}}');
    expect(
      t.fill({'first': r'$1 {{second}}', 'second': 'ok'}),
      r'$1 {{second}} / ok',
    );
  });
  test('blank values are missing while 0 is a real value', () {
    final t = PromptTemplate('{{a}} {{b}}');
    expect(t.missing({'a': '  ', 'b': '0'}), ['a']);
    expect(t.fill({'a': '  ', 'b': '0'}), '{{a}} 0');
  });
  test('slot names have a bounded grammar', () {
    expect(PromptTemplate('{{${'a' * 41}}}').slots, isEmpty);
    expect(PromptTemplate('{{two\nlines}}').slots, isEmpty);
    expect(PromptTemplate('{{file_name-1}}').slots, ['file_name-1']);
  });
  test('malformed records are repairable, never converted into valid empty prompts', () {
    for (final raw in <Map<String, Object?>>[
      {},
      {'v': 99},
      {'v': 1, 'body': 4},
      {'v': 1, 'title': 'x', 'body': ' '},
      {'v': 1, 'title': 'x', 'body': 'a' * 50001},
    ]) {
      final p = PromptEntry('a', raw);
      expect(p.valid, isFalse);
      expect(() => p.history, returnsNormally);
    }
  });
  test(
    'search handles Persian Arabic variants, notes, category and whitespace',
    () {
      final p = PromptEntry('a', {
        'title': 'طراحی',
        'category': 'بسته بندی',
        'notes': 'My NOTE',
      });
      expect(p.matches('طراحي'), isTrue);
      expect(p.matches('بسته   بندی'), isTrue);
      expect(p.matches('my note'), isTrue);
    },
  );
  test('history skips malformed snapshots and is bounded', () {
    final p = PromptEntry('a', {
      'history': [
        null,
        3,
        <String, Object?>{},
        for (var i = 0; i < 30; i++)
          {'title': '$i', 'body': 'old', 'future': true},
      ],
    });
    expect(p.history.length, 10);
    expect(p.history.first['future'], true);
  });
}
