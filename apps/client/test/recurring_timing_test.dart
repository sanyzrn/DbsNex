import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/recurring_timing.dart';

void main() {
  final now = DateTime(2026, 11, 2, 12);
  for (final locale in ['en', 'fa']) {
    test('$locale: hourly, daily, overdue and rounding boundaries', () async {
      final l = await AppLocalizations.delegate.load(Locale(locale));
      String at(Duration delta) =>
          nexRecurringCountdown(l, now.add(delta), now);
      expect(at(Duration.zero), l.commitmentDueNow);
      expect(
        at(const Duration(seconds: 1)),
        l.commitmentDueIn(l.spanMinutes(1)),
      );
      expect(
        at(const Duration(minutes: 59, seconds: 59)),
        l.commitmentDueIn(l.spanHours(1)),
      );
      expect(
        at(const Duration(hours: 1, minutes: 29, seconds: 1)),
        l.commitmentDueIn('${l.spanHours(1)} · ${l.spanMinutes(30)}'),
      );
      expect(
        at(const Duration(days: 2, hours: 3)),
        l.commitmentDueIn('${l.spanDays(2)} · ${l.spanHours(3)}'),
      );
      expect(at(const Duration(days: 80)), l.commitmentDueIn(l.spanDays(80)));
      expect(
        at(const Duration(minutes: -15)),
        l.commitmentOverdue(l.spanMinutes(15)),
      );
    });
  }
}
