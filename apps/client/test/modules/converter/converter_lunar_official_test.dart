import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/converter/converter_date.dart';

/// The lunar calendar is the one part of this module that cannot be right by
/// arithmetic alone: Iran's official month starts follow the sighting
/// announced by the Leader's Office, not a calculation. This test holds the
/// tabular calendar the module uses against 32 announced month starts from
/// 1440 to 1447 AH and records exactly how far apart they were, so the
/// README's claim ("a day either way, in the years checked") is a measurement
/// rather than a hope.
///
/// Sources for each date are in the module README's Research section.
final _officialIranianStarts = <(int, int, DateTime)>[
  // 1440
  (1440, 9, DateTime.utc(2019, 5, 7)), // 1 Ramadan
  (1440, 10, DateTime.utc(2019, 6, 5)), // 1 Shawwal, Eid al-Fitr
  (1440, 1, DateTime.utc(2018, 9, 11)), // 1 Muharram
  (1440, 12, DateTime.utc(2019, 8, 3)), // 1 Dhu al-Hijjah
  // 1441
  (1441, 9, DateTime.utc(2020, 4, 25)),
  (1441, 10, DateTime.utc(2020, 5, 24)),
  (1441, 1, DateTime.utc(2019, 9, 1)),
  (1441, 12, DateTime.utc(2020, 7, 22)),
  // 1442
  (1442, 9, DateTime.utc(2021, 4, 14)),
  (1442, 10, DateTime.utc(2021, 5, 13)),
  (1442, 1, DateTime.utc(2020, 8, 21)),
  (1442, 12, DateTime.utc(2021, 7, 11)),
  // 1443
  (1443, 9, DateTime.utc(2022, 4, 3)),
  (1443, 10, DateTime.utc(2022, 5, 2)),
  (1443, 1, DateTime.utc(2021, 8, 10)),
  (1443, 12, DateTime.utc(2022, 7, 1)),
  // 1444
  (1444, 9, DateTime.utc(2023, 3, 23)),
  (1444, 10, DateTime.utc(2023, 4, 22)),
  (1444, 1, DateTime.utc(2022, 7, 30)),
  (1444, 12, DateTime.utc(2023, 6, 20)),
  // 1445
  (1445, 9, DateTime.utc(2024, 3, 12)),
  (1445, 10, DateTime.utc(2024, 4, 10)),
  (1445, 1, DateTime.utc(2023, 7, 19)),
  (1445, 12, DateTime.utc(2024, 6, 8)),
  // 1446
  (1446, 9, DateTime.utc(2025, 3, 2)),
  (1446, 10, DateTime.utc(2025, 3, 31)),
  (1446, 1, DateTime.utc(2024, 7, 7)),
  (1446, 12, DateTime.utc(2025, 5, 28)),
  // 1447
  (1447, 9, DateTime.utc(2026, 2, 19)),
  (1447, 10, DateTime.utc(2026, 3, 21)),
  (1447, 1, DateTime.utc(2025, 6, 27)),
  (1447, 12, DateTime.utc(2026, 5, 18)),
];

void main() {
  test('every checked official month start is at most a day away', () {
    var exact = 0;
    var earlier = 0;
    var later = 0;
    for (final (year, month, actual) in _officialIranianStarts) {
      final computed = converterLunarToCivil(year, month, 1);
      final day = DateTime.utc(computed.year, computed.month, computed.day);
      final difference = day.difference(actual).inDays;
      expect(
        difference.abs(),
        lessThanOrEqualTo(1),
        reason:
            '$year/$month is ${actual.toIso8601String()}, computed '
            '${day.toIso8601String()}',
      );
      switch (difference) {
        case 0:
          exact++;
        case < 0:
          earlier++;
        default:
          later++;
      }
    }
    // What the README records: 20 of the 32 exact, 8 a day early, 4 a day
    // late. If a change to the arithmetic moves these numbers, that line has
    // to move with it.
    expect(_officialIranianStarts, hasLength(32));
    expect(exact, 20);
    expect(earlier, 8);
    expect(later, 4);
  });

  test('the month before a checked start is the one it follows', () {
    for (final (year, month, _) in _officialIranianStarts) {
      final previous = month == 1 ? 12 : month - 1;
      final previousYear = month == 1 ? year - 1 : year;
      final start = converterLunarToCivil(year, month, 1);
      final before = converterLunarToCivil(previousYear, previous, 1);
      final startDay = DateTime.utc(start.year, start.month, start.day);
      final beforeDay = DateTime.utc(before.year, before.month, before.day);
      final length = startDay.difference(beforeDay).inDays;
      expect(length, anyOf(29, 30), reason: '$previousYear/$previous');
    }
  });
}
