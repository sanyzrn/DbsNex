import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'strings.dart';
import 'fund_text.dart';

/// Keeps a fund manager's two alerts monthly (2.8.4).
///
/// The alerts are set once, for a day and a time, but a fund's contribution
/// and draw days come round every month. When Nex starts or returns (the
/// module's `keepUp`), an alert whose day has passed moves to the fund's next
/// contribution or draw day, at the same time of day. One cleared by the
/// manager has no record and stays off; one whose fund is gone is left to
/// the platform, which cancels alerts with their source.
abstract final class FundReminderUpkeep {
  static const kinds = {
    'fund-contribution': 'payReminder',
    'fund-draw': 'drawReminder',
  };

  /// The next [day] of a fund month at [hour]:[minute] that is still ahead
  /// of [now].
  static DateTime nextRing(DateTime now, int day, int hour, int minute) {
    var month = fundMonth(now);
    for (var i = 0; i < 3; i++, month = month.shift(1)) {
      final date = dueDay(month, day);
      final at = DateTime(date.year, date.month, date.day, hour, minute);
      if (at.isAfter(now)) return at;
    }
    final date = dueDay(month, day);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static Future<void> roll(
    NexModuleStore store,
    AppLocalizations l10n, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final funds = {
      for (final fund in (await store.list('fund')).map(Fund.read).nonNulls)
        fund.id: fund,
    };
    for (final record in await store.list('__reminder')) {
      final split = record.id.indexOf(':');
      if (split < 0) continue;
      final label = kinds[record.id.substring(0, split)];
      final fund = funds[record.id.substring(split + 1)];
      final rang = DateTime.tryParse('${record.body['at']}')?.toLocal();
      if (label == null || fund == null || rang == null) continue;
      // Only once its day is over: the alert of today may still be in the
      // shade, and moving it the same day would only confuse.
      if (!rang.isBefore(today)) continue;
      final day = label == 'payReminder' ? fund.paymentDay : fund.drawDay;
      final next = nextRing(at, day, rang.hour, rang.minute);
      final title = fundStrings.text(l10n, label, {'fund': fund.name});
      final persian = l10n.localeName.startsWith('fa');
      await store.setReminder(
        record.id,
        sourceKind: 'fund',
        sourceId: fund.id,
        at: next,
        title: title,
        body:
            '$title${fundSepFor(persian: persian)}${nexReadableDate(next, solar: true, persian: persian)}',
      );
    }
  }
}
