import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';

/// The on-device model was asked "چند روز به پریودی من مونده؟" with Cycle
/// shared, and answered "209 days" from nowhere; asked again, it wrote its
/// lookup as `[nex]` and a block the parser did not know, which the chat
/// then showed as raw JSON. What is pinned down here is the part the app
/// now does for it, and the shapes it is now understood in.
void main() {
  group('a question about the cycle', () {
    test('is recognised in Persian, however it is spelled', () {
      for (final question in [
        'چند روز به پریودی من مونده؟',
        'قاعدگی بعدی کیه',
        'عادت ماهانه‌ام کی شروع میشه',
        'روز تخمک‌گذاری من کیه؟',
        'تخمک گذاری',
        'چرخه‌ام منظمه؟',
        // Arabic yeh and kaf, as some keyboards type them.
        'پريود من كي مياد',
      ]) {
        expect(looksLikeCycleQuestion(question), isTrue, reason: question);
      }
    });

    test('and in English', () {
      for (final question in [
        'When is my next period?',
        'am I ovulating',
        'how long is my cycle',
        'my fertile window',
      ]) {
        expect(looksLikeCycleQuestion(question), isTrue, reason: question);
      }
    });

    test('but not everything else', () {
      for (final question in [
        'خلاصه یادداشت‌های امروزم',
        'remind me to buy milk',
        'recycle the old notes',
        'what did I write about the dentist',
      ]) {
        expect(looksLikeCycleQuestion(question), isFalse, reason: question);
      }
    });
  });

  group('a lookup written loosely', () {
    test('a fence tagged [nex] is still a block', () {
      final action = parseAssistantActions(
        '```[nex]\n{"action": "cycle"}\n```',
      ).single;
      expect(action.kind, AssistantActionKind.cycle);
    });

    test('a [nex] line above an untagged fence is still a block', () {
      final action = parseAssistantActions(
        '[nex]\n\n```\n{"action": "search", "query": "cycle"}\n}\n```',
      ).single;
      expect(action.kind, AssistantActionKind.search);
      expect(action.text, 'cycle');
    });

    test('a stray brace after the object does not lose it', () {
      final action = parseAssistantActions(
        '```nex\n{"action": "cycle"}\n}\n```',
      ).single;
      expect(action.kind, AssistantActionKind.cycle);
    });

    test('an untagged fence alone is still only quoted (AI-06)', () {
      expect(
        parseAssistantActions('```\n{"action": "delete", "id": "n1"}\n```'),
        isEmpty,
      );
    });

    test('and once read, none of it is left to show', () {
      expect(withoutActionBlock('```[nex]\n{"action": "cycle"}\n```'), isEmpty);
      expect(
        withoutActionBlock('[nex]\n```\n{"action": "cycle"}\n```'),
        isEmpty,
      );
    });
  });

  test('the short protocol shows the Cycle lookup on its own', () {
    expect(assistantActionPromptCompact, contains('{"action": "cycle"}'));
  });
}
