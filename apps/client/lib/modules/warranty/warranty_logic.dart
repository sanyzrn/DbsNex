import 'package:nex_client/modules/module_api.dart';

import 'local_values.dart';
import 'warranty_models.dart';

/// The coverage arithmetic and the money display, kept free of widgets so
/// they can be tested on their own. Dates are whole days: a coverage that
/// ends on the 15th covers the person through the 15th.
class WarrantyLogic {
  const WarrantyLogic._();

  /// [months] after [purchase], as a person reads "6 months' warranty":
  /// the same day of the ending month, or its last day when that month
  /// has no such day — January 31 + 1 month is February 28 (29 in a leap
  /// year), never March 3.
  static DateTime addMonths(DateTime purchase, int months) {
    if (months <= 0) {
      return purchase;
    }
    if (months > 2400 ||
        purchase.year + (purchase.month + months - 1) ~/ 12 > 2100) {
      throw RangeError('Coverage exceeds supported range');
    }
    var year = purchase.year;
    var month = purchase.month + months;
    year += (month - 1) ~/ 12;
    month = (month - 1) % 12 + 1;
    final day = purchase.day < _daysInMonth(year, month)
        ? purchase.day
        : _daysInMonth(year, month);
    return DateTime(year, month, day);
  }

  static int _daysInMonth(int year, int month) {
    final next = month == 12
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime.utc(year, month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }

  // ------------------------------------------------------ status on view

  /// Where a purchase sits today: covered through its end day, expiring
  /// within the window, or past it. Determined on view, never scheduled.
  static ({bool expired, bool expiring, int daysLeft}) statusOf(
    DateTime coverageEnd,
    DateTime now,
  ) {
    final today = LocalValues.civil(now.toLocal());
    final end = LocalValues.civil(coverageEnd);
    if (end.isBefore(today)) {
      return (
        expired: true,
        expiring: false,
        daysLeft: end.difference(today).inDays,
      );
    }
    final daysLeft = end.difference(today).inDays;
    return (
      expired: false,
      expiring: daysLeft <= WarrantyModels.expiringWindowDays,
      daysLeft: daysLeft,
    );
  }

  /// Whether a coverage end makes sense after its purchase: the end day
  /// must be the purchase day or later.
  static bool endAfterPurchase(DateTime purchase, DateTime end) {
    final p = LocalValues.civil(purchase);
    final e = LocalValues.civil(end);
    return !e.isBefore(p);
  }

  /// The list split into what a person needs to act on first: ending within
  /// the 30-day window (soonest first), still comfortably covered (soonest
  /// first), already ended (most recently ended first) and without a
  /// readable end. Sorting here rather than in the screen keeps the "what
  /// runs out first" question in one tested place.
  static ({
    List<ModuleRecord> expiring,
    List<ModuleRecord> covered,
    List<ModuleRecord> expired,
    List<ModuleRecord> unknown,
  })
  splitByStatus(
    List<ModuleRecord> records,
    DateTime now, {
    bool sorted = false,
  }) {
    final expiring = <ModuleRecord>[];
    final covered = <ModuleRecord>[];
    final expired = <ModuleRecord>[];
    final unknown = <ModuleRecord>[];
    for (final record in records) {
      final end = WarrantyModels.readDate(record.body, 'coverageEnd');
      if (end == null) {
        unknown.add(record);
        continue;
      }
      final status = statusOf(end, now);
      if (status.expired) {
        expired.add(record);
      } else if (status.expiring) {
        expiring.add(record);
      } else {
        covered.add(record);
      }
    }
    return (
      // The 30-day list is always ordered by what runs out first: that is
      // the question it answers, whatever the rest of the page is sorted by.
      expiring: soonestEndFirst(expiring),
      covered: sorted ? soonestEndFirst(covered) : covered,
      // The one that ended yesterday is the one a person is still dealing
      // with, so the most recent end comes first.
      expired: sorted ? latestEndFirst(expired) : expired,
      unknown: unknown,
    );
  }

  // ------------------------------------------------------------- reminders

  /// The days before the end the editor offers: thirty days, a week, a day.
  /// They are the lead times the trackers people already use recommend.
  static const reminderLeadDays = [30, 7, 1];

  /// The moment a reminder for [end] fires when it is set [daysBefore]
  /// days early: 09:00 local on that day, the hour the app's other
  /// reminders use.
  static DateTime reminderAt(DateTime end, int daysBefore, {int hour = 9}) =>
      DateTime(end.year, end.month, end.day - daysBefore, hour);

  /// The lead times still worth offering for [end] at [now]: a reminder
  /// whose moment has already passed cannot be set and is not shown.
  static List<int> reminderChoices(DateTime end, DateTime now) => [
    for (final days in reminderLeadDays)
      if (reminderAt(end, days).isAfter(now)) days,
  ];

  // ------------------------------------------------------------- money

  /// Rials as tomans, exactly: 1 toman is 10 rials, and a number of rials
  /// not divisible by ten keeps its half — 15 rials is "1.5".
  static String tomans(int rials) {
    final rest = rials % 10;
    return rest == 0 ? '${rials ~/ 10}' : '${rials ~/ 10}.$rest';
  }

  static int? rialsFromTomans(int tomans) {
    if (tomans < 0 || tomans > LocalValues.maxExact ~/ 10) {
      return null;
    }
    return tomans * 10;
  }

  /// Digits grouped in threes for reading: 30000000 -> "30,000,000".
  static String grouped(int value) {
    final text = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      final left = text.length - 1 - i;
      if (left > 0 && left % 3 == 0) buffer.write(',');
    }
    return value < 0 ? '-$buffer' : '$buffer';
  }

  /// How a query and a field are compared: the shared fold turns Arabic
  /// yeh and kaf, the Persian digits and the half-space into what a Persian
  /// reader means by the same word, so a keyboard that types «ك» still
  /// finds «ک». It is only for matching — what the person wrote is what
  /// the screen shows.
  static String fold(String text) => nexSearchFold(text).trim().toLowerCase();

  /// Search by product, brand, model, serial, invoice reference, merchant
  /// or warranty company, case-blind and script-folded; an empty query
  /// matches all. The company, the serial and the invoice are included
  /// because that is how a purchase is looked for at a service desk: a
  /// card in the hand, a serial on the box, a number on the bill.
  static bool matchesQuery(Map<String, Object?> body, String query) {
    final q = fold(query);
    if (q.isEmpty) {
      return true;
    }
    for (final key in const [
      'product',
      'brand',
      'model',
      'serial',
      'receiptRef',
      'merchant',
      'company',
    ]) {
      if (fold(WarrantyModels.readString(body, key)).contains(q)) {
        return true;
      }
    }
    return false;
  }

  /// Purchases by soonest coverage end first — the order the "expiring"
  /// question is asked in. A purchase with no readable end goes last, and
  /// equal ends keep the list's own newest-first order rather than the
  /// accidental order of an unstable sort.
  static List<ModuleRecord> soonestEndFirst(List<ModuleRecord> records) {
    final pairs = [for (var i = 0; i < records.length; i++) (records[i], i)];
    pairs.sort((a, b) {
      final aEnd = WarrantyModels.readDate(a.$1.body, 'coverageEnd');
      final bEnd = WarrantyModels.readDate(b.$1.body, 'coverageEnd');
      final byEnd = (aEnd ?? _noEndDate).compareTo(bEnd ?? _noEndDate);
      return byEnd != 0 ? byEnd : a.$2.compareTo(b.$2);
    });
    return [for (final pair in pairs) pair.$1];
  }

  /// Purchases by latest coverage end first, for the ones already ended.
  static List<ModuleRecord> latestEndFirst(List<ModuleRecord> records) {
    final pairs = [for (var i = 0; i < records.length; i++) (records[i], i)];
    pairs.sort((a, b) {
      final aEnd = WarrantyModels.readDate(a.$1.body, 'coverageEnd');
      final bEnd = WarrantyModels.readDate(b.$1.body, 'coverageEnd');
      final byEnd = (bEnd ?? _noEndDate).compareTo(aEnd ?? _noEndDate);
      return byEnd != 0 ? byEnd : a.$2.compareTo(b.$2);
    });
    return [for (final pair in pairs) pair.$1];
  }

  /// Where a purchase without a readable end sits in the soonest order:
  /// after every dated one.
  static final _noEndDate = DateTime(9999);
}
