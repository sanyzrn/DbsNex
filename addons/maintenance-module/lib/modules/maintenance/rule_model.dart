part of 'models.dart';

class IntervalRule {
  const IntervalRule({
    required this.id,
    required this.assetId,
    required this.task,
    this.days,
    this.months,
    this.meters,
    this.hours,
    this.meterUnit,
    this.meterScale = 1,
    this.source,
  });

  final String id;
  final String assetId;
  final String task;

  /// Every N days, or null.
  final int? days;

  /// Every N months (clamped at month ends), or null.
  final int? months;

  /// Every N units of [meterUnit], or null.
  final int? meters;

  /// Every N running hours, or null.
  final int? hours;

  /// The unit [meters] counts in — the asset's chosen unit when the
  /// rule was saved, kept on the rule so a unit change never
  /// reinterprets it.
  final DistanceUnit? meterUnit;

  final int meterScale;
  final Map<String, Object?>? source;
  int? get usageMilli => toMeterMilli(meters ?? hours, meterScale);

  /// A rule must say something.
  bool get hasTime => days != null || months != null;
  bool get hasUsage => meters != null || hours != null;

  Map<String, Object?> toBody() => {
    'assetId': assetId,
    'task': task,
    if (days != null) 'days': days,
    if (months != null) 'months': months,
    if (meters != null) 'meters': meters,
    if (hours != null) 'hours': hours,
    if (hasUsage) 'meter_scale': meterScale,
    if (meters != null && meterUnit != null) 'meterUnit': meterUnit!.name,
    'schema': 2,
  };

  static IntervalRule? fromBody(String id, Map<String, Object?> body) {
    final assetId = _stringOf(body, 'assetId');
    final task = _stringOf(body, 'task')?.trim();
    if (assetId == null || task == null || task.isEmpty) return null;
    final days = body['days'];
    final months = body['months'];
    final meters = body['meters'];
    final hours = body['hours'];
    final meterUnitName = _stringOf(body, 'meterUnit');
    final meterUnit = switch (meterUnitName) {
      'km' => DistanceUnit.km,
      'mi' => DistanceUnit.mi,
      _ => null,
    };
    final scale = body['meter_scale'] ?? 1;
    if (!validMeterScale(scale) ||
        (days != null && months != null) ||
        (meters != null && hours != null)) {
      return null;
    }
    if (days != null && (days is! int || days <= 0 || days > maxIntervalDays)) {
      return null;
    }
    if (months != null &&
        (months is! int || months <= 0 || months > maxIntervalMonths)) {
      return null;
    }
    for (final value in [meters, hours]) {
      if (value != null &&
          (value is! int || value <= 0 || value > meterMax * (scale as int))) {
        return null;
      }
    }
    if (days == null && months == null && meters == null && hours == null) {
      return null;
    }
    if (meters != null && meterUnit == null) return null;
    return IntervalRule(
      id: id,
      assetId: assetId,
      task: task,
      days: days is int && days > 0 ? days : null,
      months: months is int && months > 0 ? months : null,
      meters: meters is int && meters > 0 ? meters : null,
      hours: hours is int && hours > 0 ? hours : null,
      meterUnit: meterUnit,
      meterScale: scale as int,
      source: Map.of(body),
    );
  }
}
