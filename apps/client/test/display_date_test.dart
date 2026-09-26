import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/display_date.dart';
import 'package:nex_client/l10n/app_localizations_fa.dart';
import 'package:nex_client/widgets/tag_label.dart';
import 'package:nex_core/nex_core.dart';

void main() {
  test('Nowruz and leap Esfand boundaries', () {
    for (final (date, year, month, day) in [
      ('2024-03-19', 1402, 12, 29),
      ('2024-03-20', 1403, 1, 1),
      ('2025-03-20', 1403, 12, 30),
      ('2025-03-21', 1404, 1, 1),
      ('2026-03-20', 1404, 12, 29),
      ('2026-03-21', 1405, 1, 1),
      ('2026-09-26', 1405, 7, 4),
      ('2000-02-29', 1378, 12, 10),
    ]) {
      expect(nexPersianDate(DateTime.parse(date)), (
        year: year,
        month: month,
        day: day,
      ), reason: date);
    }
  });
  test(
    'digits follow language independently of calendar; includes exact time',
    () {
      final date = DateTime(2026, 9, 26, 14, 3, 9);
      expect(
        nexDisplayDate(
          date,
          solar: true,
          persian: true,
          time: true,
          seconds: true,
        ),
        '۱۴۰۵/۰۷/۰۴  ۱۴:۰۳:۰۹',
      );
      expect(nexDisplayDate(date), '2026/09/26');
      expect(nexDisplayDate(DateTime(9999), solar: true), '9999/01/01');
    },
  );
  test('starter tag labels never rename normal or renamed user tags', () {
    final fa = AppLocalizationsFa();
    Tag tag(String id, String name) =>
        Tag(id: id, name: name, createdAt: DateTime(2026));
    expect(nexTagLabel(tag(stableUuidV5('Idea'), 'Idea'), fa), 'ایده');
    expect(nexTagLabel(tag('user-id', 'Idea'), fa), 'Idea');
    expect(nexTagLabel(tag(stableUuidV5('Idea'), 'Work'), fa), 'Work');
    expect(nexTagLabel(tag('user-id', 'برنامه'), fa), 'برنامه');
  });
}
