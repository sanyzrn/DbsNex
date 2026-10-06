import 'cycle_models.dart';

/// What «Cycle» is for right now.
enum CycleMode {
  /// Following the cycle: predictions, the fertile window, alerts.
  normal,

  /// Trying to conceive: the same, with the fertile window put first.
  conceive,

  /// Pregnant: weeks and the due date instead of predictions.
  pregnant,

  /// Breastfeeding: periods are often absent or irregular, so nothing is
  /// predicted; logging goes on as always.
  breastfeeding,

  /// Perimenopause or menopause: likewise, logging only.
  menopause;

  static CycleMode fromWire(String? value) {
    for (final mode in values) {
      if (mode.name == value) return mode;
    }
    return normal;
  }

  /// Whether the next period, the fertile window and the alerts mean
  /// anything in this mode.
  bool get predicts => this == normal || this == conceive;
}

/// How far along a pregnancy is, counted the way doctors count it: from the
/// first day of the last period, forty weeks to the due date.
class CyclePregnancy {
  const CyclePregnancy({required this.lastPeriod, required this.today});

  /// The first day of the last period before the pregnancy.
  final CycleDate lastPeriod;
  final CycleDate today;

  /// The length of a pregnancy by this count.
  static const term = 280;

  /// From a due date, the last period it implies.
  static CycleDate lastPeriodFor(CycleDate dueDate) => dueDate.addDays(-term);

  int get daysAlong => today.daysSince(lastPeriod).clamp(0, term + 42);
  int get weeks => daysAlong ~/ 7;
  int get days => daysAlong % 7;
  CycleDate get dueDate => lastPeriod.addDays(term);
  int get daysToGo => dueDate.daysSince(today);

  /// 1, 2 or 3: up to the end of week 13, of week 27, and after.
  int get trimester => weeks < 14
      ? 1
      : weeks < 28
      ? 2
      : 3;

  /// How much of the forty weeks has passed, 0 to 1.
  double get fraction => (daysAlong / term).clamp(0.0, 1.0);
}
