import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  CloudAIAdapter adapter(
    String answer, {
    String finish = 'stop',
    void Function()? onCall,
  }) => CloudAIAdapter(
    config: const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
    client: MockClient((request) async {
      onCall?.call();
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'choices': [
              {
                'message': {'content': answer},
                'finish_reason': finish,
              },
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  for (final style in NexRewriteStyle.values) {
    test(
      '${style.name} accepts complete Persian text and preserves key values',
      () async {
        const source =
            'پرژه لغو نشده. توسعه ادامه دارد. بودجه ۱۰۰۰۰ و موعد ۱۵ آبان.';
        const edited =
            'پروژه لغو نشده و توسعه ادامه دارد. بودجه: ۱۰۰۰۰؛ موعد: ۱۵ آبان.';
        var calls = 0;
        final ai = adapter(edited, onCall: () => calls++);
        addTearDown(ai.close);
        expect(await ai.rewrite(source, style: style), edited);
        expect(calls, 1);
      },
    );
  }
  test('changed or missing values never replace a draft', () async {
    final ai = adapter('Budget 9000, due 15.');
    addTearDown(ai.close);
    expect(
      await ai.rewrite('Budget 10000, due 15.', style: NexRewriteStyle.concise),
      isNull,
    );
  });
  test('incomplete replies are rejected', () async {
    final ai = adapter('Partial text', finish: 'length');
    addTearDown(ai.close);
    expect(
      await ai.rewrite(
        'The complete original.',
        style: NexRewriteStyle.autoStyle,
      ),
      isNull,
    );
    expect(ai.lastReplyTruncated, isTrue);
  });
  test('valid zeros, markdown rules and long addresses are accepted', () async {
    const text =
        '## Budget\n\n10000\n\n----\nhttps://example.com/abcdefghijklmnopqrstuvwxyzabcdef';
    final ai = adapter(text);
    addTearDown(ai.close);
    expect(await ai.rewrite(text, style: NexRewriteStyle.fix), text);
  });
  test('oversized text is refused before sending', () async {
    var calls = 0;
    final ai = adapter('answer', onCall: () => calls++);
    addTearDown(ai.close);
    await expectLater(
      ai.rewrite('word ' * 2500, style: NexRewriteStyle.autoStyle),
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
}
