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

  /// Search by product or brand, case-blind; an empty query matches all.
  static bool matchesQuery(Map<String, Object?> body, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return true;
    }
    return WarrantyModels.readString(
          body,
          'product',
        ).toLowerCase().contains(q) ||
        WarrantyModels.readString(body, 'brand').toLowerCase().contains(q);
  }

  /// Purchases by soonest coverage end first — the order the "expiring"
  /// question is asked in.
  static List<Map<String, Object?>> soonestFirst(
    Iterable<Map<String, Object?>> bodies,
  ) {
    final list = bodies.toList()
      ..sort((a, b) {
        final aEnd = WarrantyModels.readDate(a, 'coverageEnd');
        final bEnd = WarrantyModels.readDate(b, 'coverageEnd');
        return (aEnd ?? DateTime(0)).compareTo(bEnd ?? DateTime(0));
      });
    return list;
  }
}
