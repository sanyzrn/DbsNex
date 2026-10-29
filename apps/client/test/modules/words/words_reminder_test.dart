import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_reminder.dart';

/// 2.4.0: the review reminder rings on the next day with words waiting, at
/// the chosen time, and never on a day with nothing to review.
void main() {
  WordCard card(String id, {String? due, bool paused = false}) =>
      WordCard.fromRecord(id, {
        'schema': 2,
        'headword': id,
        'language': 'English',
        'meaning': 'm',
        'createdAt': '2026-10-01T09:00:00',
        'step': due == null ? 0 : 1,
        'due': ?due,
        'reps': due == null ? 0 : 1,
        'lapses': 0,
        if (due != null) 'lastReview': '2026-10-20T09:00:00',
        if (due != null) 'introducedOn': '2026-10-20',
        'paused': paused,
        'log': const [],
      });

  final morning = DateTime(2026, 10, 29, 8);
  final evening = DateTime(2026, 10, 29, 21);

  test('today, at the time, when a word is due today', () {
    final next = wordsNextReminder(
      [card('a', due: '2026-10-29')],
      minutes: 20 * 60,
      newPerDay: 10,
      now: morning,
    );
    expect(next!.at, DateTime(2026, 10, 29, 20));
    expect(next.count, 1);
  });

  test('past today\'s time it waits for the next day with words', () {
    final next = wordsNextReminder(
      [card('a', due: '2026-11-02')],
      minutes: 20 * 60,
      newPerDay: 10,
      now: evening,
    );
    expect(next!.at, DateTime(2026, 11, 2, 20));
  });

  test('new words count, up to the daily allowance; paused ones do not', () {
    final next = wordsNextReminder(
      [
        card('a'),
        card('b'),
        card('c'),
        card('d', due: '2026-10-29', paused: true),
      ],
      minutes: 20 * 60,
      newPerDay: 2,
      now: morning,
    );
    expect(next!.count, 2);
  });

  test('nothing waiting, no reminder', () {
    expect(
      wordsNextReminder(
        [card('a', paused: true)],
        minutes: 20 * 60,
        newPerDay: 10,
        now: morning,
      ),
      isNull,
    );
  });
}
