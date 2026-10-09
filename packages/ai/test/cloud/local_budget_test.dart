import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_ai/src/cloud/local_budget.dart';
import 'package:nex_core/nex_core.dart';

/// The on-device model's window is 4,096 tokens, and a request that did not
/// fit was refused with "Input token ids are too long: 4707 >= 4096" — which
/// the chat showed as a model that would not start. What is tested here is
/// that every request the phone is given now fits, and what gives way.
void main() {
  // A Persian note line, as the chat sheet writes one: id, text, tags.
  String persianNote(int i) =>
      '[n$i] ${'یادداشت درباره‌ی خرید و کارهای خانه و قرار دکتر ' * 8} #خانه';
  int cost(String text) => LocalBudget.estimate(text);

  group('estimating', () {
    test('Persian costs more per character than Latin', () {
      // It does for Gemma's tokenizer, and an estimate that treated them
      // alike would let a Persian request over the edge.
      expect(cost('سلام' * 100), greaterThan(cost('abcd' * 100)));
    });

    test('a cut text fits, and says it was cut', () {
      final text = 'کتاب ' * 2000;
      final cut = LocalBudget.clip(text, 200);
      expect(cost(cut), lessThanOrEqualTo(200));
      expect(cut, endsWith('…'));
      expect(LocalBudget.clip('short', 200), 'short');
    });
  });

  group('the notes', () {
    test('the ones found for the question are kept before the recent', () {
      final context = [
        for (var i = 0; i < 20; i++) persianNote(i),
        '',
        'Notes matching the latest question, best match first:',
        '[found1] the dentist on Monday at 5',
        '[found2] tooth pain since last week',
      ].join('\n');

      final fitted = LocalBudget.fitNotes(context, 300);

      expect(cost(fitted), lessThanOrEqualTo(320));
      expect(fitted, contains('[found1]'));
      expect(fitted, contains('[found2]'));
      expect(fitted, isNot(contains('[n19]')));
    });
  });

  test('a chat about one note sees the note, not ninety tokens of it '
      '(AI-04)', () {
    final focus = '[n1] ${'یک یادداشت بلند درباره‌ی سفر ' * 80}';
    final fitted = LocalBudget.fitNotes(focus, 1500);
    expect(cost(fitted), greaterThan(900));
    expect(cost(fitted), lessThanOrEqualTo(1500));
  });

  group('the conversation', () {
    test('the newest question always stays; the oldest turns go', () {
      final turns = [
        for (var i = 0; i < 30; i++) ...[
          ChatMessage(role: ChatRole.user, content: 'question $i ${'x' * 300}'),
          ChatMessage(
            role: ChatRole.assistant,
            content: 'answer $i ${'y' * 300}',
          ),
        ],
        const ChatMessage(role: ChatRole.user, content: 'the newest question'),
      ];

      final fitted = LocalBudget.fitTurns(turns, reserved: 2000);

      expect(fitted.last.content, 'the newest question');
      expect(
        fitted.first.role,
        ChatRole.user,
        reason: 'never opens on a reply',
      );
      final total = fitted.fold(0, (sum, t) => sum + cost(t.content));
      expect(total, lessThanOrEqualTo(LocalBudget.input - 2000));
      expect(fitted.length, lessThan(turns.length));
    });

    test('a lookup cut short still reads as data', () {
      final findings = '<<<NOTES\n${'Results for "x":\n' * 400}NOTES>>>';
      final fitted = LocalBudget.fitTurns([
        ChatMessage(role: ChatRole.user, content: findings),
      ], reserved: 0);
      expect(fitted.single.content, startsWith('<<<NOTES\n'));
      expect(fitted.single.content, endsWith('\nNOTES>>>'));
      expect(cost(fitted.single.content), lessThanOrEqualTo(900));
    });
  });

  group('a whole chat request for the phone', () {
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(),
      outputLanguage: AiOutputLanguage.persian,
    );
    final options = AiChatOptions(
      canAct: true,
      notesContext: [
        for (var i = 0; i < 20; i++) persianNote(i),
        '',
        'Notes matching the latest question, best match first:',
        for (var i = 0; i < 8; i++) persianNote(100 + i),
      ].join('\n'),
    );
    final history = [
      for (var i = 0; i < 12; i++) ...[
        ChatMessage(role: ChatRole.user, content: 'سؤال $i ${'چرا ' * 60}'),
        ChatMessage(
          role: ChatRole.assistant,
          content: 'جواب $i ${'چون ' * 80}',
        ),
      ],
      const ChatMessage(role: ChatRole.user, content: 'خودت رو معرفی کن'),
    ];

    test('fits the window, the case that was refused at 4707 tokens', () {
      final fitted = adapter.fitForLocal(options, history);
      final total =
          cost(fitted.system) +
          fitted.turns.fold(0, (sum, t) => sum + cost(t.content));
      expect(total, lessThanOrEqualTo(LocalBudget.input));
      expect(fitted.turns.last.content, 'خودت رو معرفی کن');
      // Still able to act, in the short form, and still told the notes are
      // data.
      expect(fitted.system, contains('```nex'));
      expect(fitted.system, contains('<<<NOTES'));
    });

    test('the language comes first, in Persian', () {
      final fitted = adapter.fitForLocal(options, history);
      expect(fitted.system, startsWith('پاسخ را کامل به فارسی بنویس.'));
    });

    test('a short request is left as it was', () {
      final fitted = adapter.fitForLocal(const AiChatOptions(), const [
        ChatMessage(role: ChatRole.user, content: 'سلام'),
      ]);
      expect(fitted.system, contains('You are the assistant inside Nex'));
      expect(fitted.turns.single.content, 'سلام');
    });
  });

  test('the short action protocol names every action the full one does', () {
    // The two are kept in step by hand; this is what notices when one is
    // given an action the other is not.
    final full = RegExp(
      r'"action": "([a-z_]+)"',
    ).allMatches(assistantActionPrompt).map((m) => m.group(1)!).toSet();
    for (final action in full) {
      expect(
        assistantActionPromptCompact,
        contains(action),
        reason: '$action is missing from the short protocol',
      );
    }
  });
}
