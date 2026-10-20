import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/occasions/occasion_model.dart';
import 'package:nex_client/modules/occasions/occasion_reminders.dart';

Occasion occasion({
  int? remindDays = 1,
  int minutes = 9 * 60,
  bool muted = false,
  bool archived = false,
  int month = 12,
  int day = 25,
  OccasionCalendar calendar = OccasionCalendar.gregorian,
}) => Occasion(
  id: 'o1',
  title: 'Sara',
  kind: OccasionKind.birthday,
  calendar: calendar,
  month: month,
  day: day,
  muted: muted,
  archived: archived,
  remindDays: remindDays,
  remindMinutes: minutes,
  createdAt: DateTime(2026),
);

void main() {
  final now = DateTime(2026, 10, 20, 12);

  test('the next two moments still ahead, one day before at nine', () {
    final alarms = occasionAlarms(occasion(), now);
    expect(alarms, [DateTime(2026, 12, 24, 9), DateTime(2027, 12, 24, 9)]);
  });

  test('on the day itself: the date, at the chosen time', () {
    final alarms = occasionAlarms(
      occasion(remindDays: 0, minutes: 8 * 60 + 30),
      now,
    );
    expect(alarms.first, DateTime(2026, 12, 25, 8, 30));
  });

  test('an alarm already past today is skipped, not set in the past', () {
    // Birthday is tomorrow; "a day before at 09:00" was this morning.
    final tomorrow = now.add(const Duration(days: 1));
    final alarms = occasionAlarms(
      occasion(month: tomorrow.month, day: tomorrow.day),
      now,
    );
    expect(alarms.first.isAfter(now), isTrue);
    expect(alarms.first.year, 2027);
    expect(alarms, hasLength(2));
  });

  test('a week before can reach back across a month end', () {
    final alarms = occasionAlarms(
      occasion(remindDays: 7, month: 11, day: 3),
      now,
    );
    expect(alarms.first, DateTime(2026, 10, 27, 9));
  });

  test(
    'none without a reminder, when muted or archived, or for a bad date',
    () {
      expect(occasionAlarms(occasion(remindDays: null), now), isEmpty);
      expect(occasionAlarms(occasion(muted: true), now), isEmpty);
      expect(occasionAlarms(occasion(archived: true), now), isEmpty);
      expect(occasionAlarms(occasion(month: 13), now), isEmpty);
    },
  );

  test('a Jalali date is followed on its Jalali day', () {
    final alarms = occasionAlarms(
      occasion(
        calendar: OccasionCalendar.jalali,
        month: 7,
        day: 15,
        remindDays: 0,
      ),
      now,
    );
    // 15 Mehr 1406 is 7 October 2027; 15 Mehr 1407 is 6 October 2028.
    expect(alarms.first.year, 2027);
    expect(alarms.first.month, 10);
    expect(alarms.last.year, 2028);
  });

  test('the two slots have their own keys', () {
    expect(occasionReminderKey('o1', 'a'), 'occ:o1:a');
    expect(occasionReminderKey('o1', 'b'), 'occ:o1:b');
  });
}
