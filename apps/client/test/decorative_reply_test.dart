import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/ai_provider.dart';

void main() {
  test(
    'reasoning envelopes and prompt echoes never become decorative content',
    () {
      for (final text in [
        'The user wants a short greeting',
        'We need to produce four lines',
        'کاربر می‌خواهد یک خوشامد کوتاه بنویسم',
        'کاربر درخواست کرده خلاصه بسازم',
        'تحلیل: باید متن را خلاصه کنم',
        'Reasoning: I should write a greeting',
        '<think>unfinished internal reasoning',
      ]) {
        expect(CloudAIAdapter.cleanDecorativeReply(text), isNull, reason: text);
      }
      expect(
        CloudAIAdapter.cleanDecorativeReply('<think>hidden</think>صبح بخیر'),
        'صبح بخیر',
      );
      expect(
        CloudAIAdapter.cleanDecorativeReply('📌 فردا جلسه داری'),
        '📌 فردا جلسه داری',
      );
      expect(
        CloudAIAdapter.cleanDecorativeReply('Remember to review the generator'),
        'Remember to review the generator',
      );
    },
  );
}
