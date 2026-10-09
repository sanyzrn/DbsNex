/// «Cycle» — the menstrual cycle assistant.
///
/// Days here are calendar days, not instants: a period starts on a date, in
/// whatever zone the person was in, and must not slide to the day before
/// because the phone crossed midnight UTC. [CycleDate] is that date.
library;

/// A calendar day: year, month, day — no time, no zone.
class CycleDate implements Comparable<CycleDate> {
  const CycleDate(this.year, this.month, this.day);

  factory CycleDate.of(DateTime when) =>
      CycleDate(when.year, when.month, when.day);

  /// From `yyyy-MM-dd`, the form it is stored in.
  factory CycleDate.parse(String text) {
    final parts = text.split('-').map(int.parse).toList();
    return CycleDate(parts[0], parts[1], parts[2]);
  }

  final int year;
  final int month;
  final int day;

  /// Midnight on this day in local time, for showing and scheduling.
  DateTime get local => DateTime(year, month, day);

  /// Noon UTC: a fixed point whose difference to another day's is always a
  /// whole number of days, whatever the daylight-saving rules.
  DateTime get _utc => DateTime.utc(year, month, day, 12);

  CycleDate addDays(int days) => CycleDate.of(_utc.add(Duration(days: days)));

  /// Whole days from [other] to this one (positive when this is later).
  int daysSince(CycleDate other) => _utc.difference(other._utc).inDays;

  bool isBefore(CycleDate other) => compareTo(other) < 0;
  bool isAfter(CycleDate other) => compareTo(other) > 0;

  @override
  int compareTo(CycleDate other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) =>
      other is CycleDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// One period: the day it started and, once it has, the day it ended
/// (inclusive). An open period is one still going.
class CyclePeriod {
  const CyclePeriod({required this.id, required this.start, this.end});

  final String id;
  final CycleDate start;
  final CycleDate? end;

  bool get isOpen => end == null;

  /// Days it lasted, counting both ends. Null while open.
  int? get length => end == null ? null : end!.daysSince(start) + 1;

  bool contains(CycleDate day) =>
      !day.isBefore(start) && (end == null || !day.isAfter(end!));

  /// Whether this period shares a day with [from]..[to] (DATA-10). An open
  /// end — this one's or the range's — counts as its start day only: it
  /// says nothing yet about the days after.
  bool overlaps(CycleDate from, CycleDate? to) {
    final last = end ?? start;
    final rangeLast = to ?? from;
    return !from.isAfter(last) && !rangeLast.isBefore(start);
  }

  /// The first of [periods], other than [id], that [from]..[to] would
  /// overlap, or null when the dates are free.
  static CyclePeriod? clash(
    Iterable<CyclePeriod> periods,
    String id,
    CycleDate from,
    CycleDate? to,
  ) {
    for (final p in periods) {
      if (p.id != id && p.overlaps(from, to)) return p;
    }
    return null;
  }
}

/// How much bleeding a day had.
enum CycleFlow {
  spotting,
  light,
  medium,
  heavy;

  static CycleFlow? fromWire(String? value) {
    for (final flow in values) {
      if (flow.name == value) return flow;
    }
    return null;
  }
}

/// An ovulation (LH) test.
enum CycleOvulationTest {
  negative,
  positive;

  static CycleOvulationTest? fromWire(String? value) {
    for (final t in values) {
      if (t.name == value) return t;
    }
    return null;
  }
}

/// Cervical mucus, from least to most fertile.
enum CycleMucus {
  dry,
  sticky,
  creamy,
  watery,
  eggWhite;

  static CycleMucus? fromWire(String? value) {
    for (final m in values) {
      if (m.name == value) return m;
    }
    return null;
  }
}

/// How a day felt, from low to high.
enum CycleMood {
  low,
  sensitive,
  calm,
  good,
  great;

  static CycleMood? fromWire(String? value) {
    for (final mood in values) {
      if (mood.name == value) return mood;
    }
    return null;
  }
}

/// The symptoms a day can carry. Stored by name, so new ones can be added
/// and old logs keep reading.
enum CycleSymptom {
  cramps,
  headache,
  backPain,
  bloating,
  breastTenderness,
  acne,
  nausea,
  fatigue,
  cravings,
  insomnia,
  dizziness,
  discharge;

  static Set<CycleSymptom> parse(String? value) => {
    for (final name in (value ?? '').split(','))
      for (final symptom in values)
        if (symptom.name == name) symptom,
  };
}

/// What was noted about one day. Every field is optional: a day logged with
/// only a mood is a day with only a mood.
class CycleDayLog {
  const CycleDayLog({
    required this.day,
    this.flow,
    this.symptoms = const {},
    this.mood,
    this.energy,
    this.painRelief = false,
    this.intimacy = false,
    this.pill = false,
    this.note,
    this.temperature,
    this.ovulationTest,
    this.mucus,
  });

  final CycleDate day;
  final CycleFlow? flow;
  final Set<CycleSymptom> symptoms;
  final CycleMood? mood;

  /// 1 (drained) to 5 (full of it).
  final int? energy;
  final bool painRelief;
  final bool intimacy;

  /// The daily pill was taken.
  final bool pill;
  final String? note;

  /// Basal body temperature on waking, in °C.
  final double? temperature;
  final CycleOvulationTest? ovulationTest;
  final CycleMucus? mucus;

  bool get isEmpty =>
      flow == null &&
      symptoms.isEmpty &&
      mood == null &&
      energy == null &&
      !painRelief &&
      !intimacy &&
      !pill &&
      temperature == null &&
      ovulationTest == null &&
      mucus == null &&
      (note?.trim().isEmpty ?? true);

  CycleDayLog copyWith({
    CycleFlow? Function()? flow,
    Set<CycleSymptom>? symptoms,
    CycleMood? Function()? mood,
    int? Function()? energy,
    bool? painRelief,
    bool? intimacy,
    bool? pill,
    String? Function()? note,
    double? Function()? temperature,
    CycleOvulationTest? Function()? ovulationTest,
    CycleMucus? Function()? mucus,
  }) => CycleDayLog(
    day: day,
    flow: flow == null ? this.flow : flow(),
    symptoms: symptoms ?? this.symptoms,
    mood: mood == null ? this.mood : mood(),
    energy: energy == null ? this.energy : energy(),
    painRelief: painRelief ?? this.painRelief,
    intimacy: intimacy ?? this.intimacy,
    pill: pill ?? this.pill,
    note: note == null ? this.note : note(),
    temperature: temperature == null ? this.temperature : temperature(),
    ovulationTest: ovulationTest == null ? this.ovulationTest : ovulationTest(),
    mucus: mucus == null ? this.mucus : mucus(),
  );
}
