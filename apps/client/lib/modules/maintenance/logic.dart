/// Derived from entered records only; a meter update never becomes a service.
library;

import 'models.dart';
import 'units.dart';
import 'costs.dart';
import 'local_values.dart';

const comingUpDays = 30;

class RuleStanding {
  const RuleStanding({
    required this.rule,
    this.lastDone,
    this.basisPurchase = false,
    this.timeDue,
    this.timeUnknown = false,
    this.nextDueMeter,
    this.currentMeter,
    this.meterUnknown = false,
    this.anchorDate,
    this.anchorMeter,
    this.readingAt,
    this.converted = false,
  });
  final IntervalRule rule;
  final ServiceEvent? lastDone;
  final bool basisPurchase, timeUnknown, meterUnknown, converted;
  final DateTime? timeDue, anchorDate, readingAt;

  /// All derived meter values have explicit scale 1000.
  final int? nextDueMeter, currentMeter, anchorMeter;
  int get meterScale => 1000;
  ({DateTime? date, int? meter}) get earliestDue => (
    date: timeUnknown ? null : timeDue,
    meter: meterUnknown ? null : nextDueMeter,
  );
  bool dueByTime(DateTime now) =>
      !timeUnknown && timeDue != null && !dayOf(timeDue!).isAfter(dayOf(now));
  bool get dueByMeter =>
      !meterUnknown &&
      currentMeter != null &&
      nextDueMeter != null &&
      currentMeter! >= nextDueMeter!;
  bool dueNow(DateTime now) => dueByTime(now) || dueByMeter;
  bool comingUp(DateTime now) {
    if (dueNow(now) || timeUnknown || timeDue == null) return false;
    final days = daysBetween(now, timeDue!);
    return days >= 0 && days <= comingUpDays;
  }

  double timeProgress(DateTime now) {
    if (timeUnknown || timeDue == null || anchorDate == null) return 0;
    final total = daysBetween(anchorDate!, timeDue!),
        done = daysBetween(anchorDate!, now);
    return total <= 0 ? 1 : (done / total).clamp(0.0, 1.0);
  }

  double get usageProgress {
    if (meterUnknown ||
        anchorMeter == null ||
        nextDueMeter == null ||
        currentMeter == null) {
      return 0;
    }
    final span = nextDueMeter! - anchorMeter!;
    return span <= 0
        ? 1
        : ((currentMeter! - anchorMeter!) / span).clamp(0.0, 1.0);
  }

  bool get unknown =>
      (rule.hasTime && timeUnknown) ||
      (rule.hasUsage && (meterUnknown || nextDueMeter == null));
}

bool serviceDateKnown(ServiceEvent event) {
  if (event.assetId.isEmpty || event.task.trim().isEmpty || event.task == '—') {
    return false;
  }
  if (event.source == null) return event.valid;
  return LocalValues.stamp(event.source!['date']) != null;
}

MeterKind eventMeterKind(ServiceEvent event) =>
    event.meterKind ??
    (event.meterUnit == null ? MeterKind.hours : MeterKind.distance);
bool validEventMeter(ServiceEvent event) =>
    event.meterValid &&
    event.meter != null &&
    validMeterScale(event.meterScale) &&
    event.meter! >= 0 &&
    event.meter! <= meterMax * event.meterScale &&
    (eventMeterKind(event) != MeterKind.distance || event.meterUnit != null);
int compareServices(ServiceEvent a, ServiceEvent b) {
  final date = b.date.compareTo(a.date);
  return date != 0 ? date : b.id.compareTo(a.id);
}

String normalizedTask(String task) =>
    task.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

List<RuleStanding> ruleStandings(
  MaintenanceAsset asset,
  List<ServiceEvent> events,
  List<IntervalRule> rules,
  DateTime now, {
  List<MaintenanceReading> readings = const [],
}) {
  final dated =
      events
          .where(
            (e) =>
                e.assetId == asset.id &&
                serviceDateKnown(e) &&
                !dayOf(e.date).isAfter(dayOf(now)),
          )
          .toList()
        ..sort(compareServices);
  return [
    for (final rule in rules.where((r) => r.assetId == asset.id))
      _standingOf(asset, dated, rule, now, readings),
  ];
}

RuleStanding _standingOf(
  MaintenanceAsset asset,
  List<ServiceEvent> events,
  IntervalRule rule,
  DateTime now,
  List<MaintenanceReading> readings,
) {
  if (IntervalRule.fromBody(rule.id, rule.toBody()) == null) {
    return RuleStanding(
      rule: rule,
      timeUnknown: rule.hasTime,
      meterUnknown: rule.hasUsage,
    );
  }
  final matching = events.where(
    (e) => normalizedTask(e.task) == normalizedTask(rule.task),
  );
  final last = matching.isEmpty ? null : matching.first;
  DateTime? due, anchor = last?.date ?? asset.purchasedAt;
  var timeUnknown = false, basis = false;
  if (rule.hasTime) {
    if (anchor == null || !asset.valid) {
      timeUnknown = true;
    } else {
      basis = last == null;
      try {
        due = rule.days != null
            ? addDays(anchor, rule.days!)
            : addMonths(anchor, rule.months!);
      } catch (_) {
        timeUnknown = true;
      }
    }
  }
  int? current, next, base;
  DateTime? readingAt;
  var unknown = false, converted = false;
  if (rule.hasUsage) {
    final kind = rule.hours != null ? MeterKind.hours : MeterKind.distance;
    final unit = rule.meterUnit;
    final contextValid =
        asset.valid &&
        asset.meterKind == kind &&
        (kind != MeterKind.distance || unit != null);
    int? inRuleUnits(int milli, DistanceUnit? from) {
      if (kind != MeterKind.distance) return milli;
      if (from == null || unit == null) return null;
      if (from != unit) converted = true;
      return convertMilli(milli, from, unit);
    }

    if (contextValid) {
      if (last != null &&
          validEventMeter(last) &&
          eventMeterKind(last) == kind) {
        base = inRuleUnits(last.meterMilli!, last.meterUnit);
      }
      final context = MaintenanceAsset(
        id: asset.id,
        nickname: asset.nickname,
        type: asset.type,
        meterKind: kind,
        distanceUnit: unit ?? asset.distanceUnit,
      );
      final entered = latestEnteredMeter(context, events, readings, now);
      if (entered != null) {
        current = entered.value;
        readingAt = entered.at;
        converted = converted || entered.converted;
      }
      if (base != null && rule.usageMilli != null) {
        next = base + rule.usageMilli!;
      }
    }
    // No service baseline is not a fabricated zero reading. A correction below
    // the service baseline needs review; it never silently resets the interval.
    unknown =
        next == null || current == null || (base != null && current < base);
  }
  return RuleStanding(
    rule: rule,
    lastDone: last,
    basisPurchase: basis,
    timeDue: due,
    timeUnknown: timeUnknown,
    nextDueMeter: next,
    currentMeter: current,
    meterUnknown: unknown,
    anchorDate: anchor,
    anchorMeter: base,
    readingAt: readingAt,
    converted: converted,
  );
}

enum AssetGroup { dueNow, comingUp, scheduled, needsInfo, noSchedule, archived }

AssetGroup assetGroupOf(
  MaintenanceAsset asset,
  List<RuleStanding> standings,
  DateTime now, {
  bool incompleteRules = false,
}) {
  if (asset.archived) return AssetGroup.archived;
  if (!asset.valid) return AssetGroup.needsInfo;
  if (standings.any((s) => s.dueNow(now))) return AssetGroup.dueNow;
  if (incompleteRules || standings.any((s) => s.unknown)) {
    return AssetGroup.needsInfo;
  }
  if (standings.isEmpty) return AssetGroup.noSchedule;
  if (standings.any((s) => s.comingUp(now))) return AssetGroup.comingUp;
  return AssetGroup.scheduled;
}

({int value, DateTime at, bool converted})? latestEnteredMeter(
  MaintenanceAsset asset,
  List<ServiceEvent> events,
  List<MaintenanceReading> readings,
  DateTime now,
) {
  if (asset.meterKind == MeterKind.none) return null;
  ({int value, DateTime at, bool converted})? result;
  void add(int value, DateTime at, DistanceUnit? unit) {
    if (at.isAfter(now.toUtc())) return;
    if (result != null && at.isBefore(result!.at.toUtc())) return;
    if (asset.meterKind == MeterKind.distance && unit == null) return;
    final converted =
        asset.meterKind == MeterKind.distance && unit != asset.distanceUnit;
    final shown = asset.meterKind == MeterKind.distance
        ? convertMilli(value, unit!, asset.distanceUnit)
        : value;
    result = (value: shown, at: at.toLocal(), converted: converted);
  }

  final ordered =
      events
          .where(
            (e) =>
                e.assetId == asset.id &&
                serviceDateKnown(e) &&
                validEventMeter(e) &&
                eventMeterKind(e) == asset.meterKind,
          )
          .toList()
        ..sort((a, b) => -compareServices(a, b));
  for (final event in ordered) {
    final stamped = event.source == null
        ? event.date
        : LocalValues.stamp(event.source!['date']) ?? event.date;
    add(event.meterMilli!, stamped.toUtc(), event.meterUnit);
  }
  final updates =
      readings
          .where((r) => r.assetId == asset.id && r.kind == asset.meterKind)
          .toList()
        // Deterministic order for same-instant readings: the id decides.
        ..sort(
          (a, b) => a.at.compareTo(b.at) != 0
              ? a.at.compareTo(b.at)
              : a.id.compareTo(b.id),
        );
  for (final reading in updates) {
    add(reading.milli, reading.at, reading.unit);
  }
  return result;
}

Map<String, BigInt> assetCostTotals(List<ServiceEvent> events) {
  final totals = <String, BigInt>{};
  for (final event in events) {
    if (!event.valid ||
        event.cost == null ||
        event.cost! < 0 ||
        event.cost! > costMax ||
        costCurrencyOf(event.currency) == null) {
      continue;
    }
    totals[event.currency!] =
        (totals[event.currency!] ?? BigInt.zero) + BigInt.from(event.cost!);
  }
  return totals;
}

ServiceEvent? latestEventOfTask(
  List<ServiceEvent> events,
  String assetId,
  String task,
) {
  final matching =
      events
          .where(
            (e) =>
                e.assetId == assetId &&
                serviceDateKnown(e) &&
                normalizedTask(e.task) == normalizedTask(task),
          )
          .toList()
        ..sort(compareServices);
  return matching.isEmpty ? null : matching.first;
}

/// Historical entries are compared to their chronological neighbors, not
/// incorrectly to the newest reading after that date. Hours are included.
bool meterGoesBackwards(
  List<ServiceEvent> events,
  String assetId,
  DistanceUnit unit,
  int reading, {
  String? excludingEventId,
  DateTime? at,
  MeterKind kind = MeterKind.distance,
  int scale = 1,
}) {
  final meters =
      events
          .where(
            (e) =>
                e.assetId == assetId &&
                e.id != excludingEventId &&
                serviceDateKnown(e) &&
                validEventMeter(e) &&
                eventMeterKind(e) == kind,
          )
          .toList()
        ..sort(compareServices);
  final entered = toMeterMilli(reading, scale)!;
  int value(ServiceEvent e) => kind == MeterKind.hours
      ? e.meterMilli!
      : convertMilli(e.meterMilli!, e.meterUnit!, unit);
  if (meters.isEmpty) return false;
  if (at == null) return entered < value(meters.first);
  final prior = meters.where((e) => !e.date.isAfter(at));
  final after = meters.where((e) => e.date.isAfter(at)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return (prior.isNotEmpty && entered < value(prior.first)) ||
      (after.isNotEmpty && entered > value(after.first));
}
