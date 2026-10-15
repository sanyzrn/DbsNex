part of 'models.dart';

/// An explicit meter update is not a service, and never resets a task interval.
class MaintenanceReading {
  const MaintenanceReading({
    required this.id,
    required this.assetId,
    required this.value,
    required this.kind,
    required this.at,
    this.unit,
    this.scale = 1000,
    this.corrected = false,
  });
  final String id, assetId;
  final int value, scale;
  final MeterKind kind;
  final DistanceUnit? unit;
  final DateTime at;
  final bool corrected;
  int get milli => toMeterMilli(value, scale)!;
  Map<String, Object?> toBody() => {
    'schema': 1,
    'assetId': assetId,
    'value': value,
    'scale': scale,
    'meterKind': kind.name,
    if (unit != null) 'unit': unit!.name,
    'at': at.toUtc().toIso8601String(),
    'corrected': corrected,
  };
  static MaintenanceReading? fromBody(String id, Map<String, Object?> body) {
    final parent = body['assetId'],
        value = body['value'],
        scale = body['scale'] ?? 1;
    final kind = body['meterKind'], at = LocalValues.stamp(body['at']);
    if (parent is! String ||
        parent.isEmpty ||
        value is! int ||
        !validMeterScale(scale) ||
        value < 0 ||
        value > meterMax * (scale as int) ||
        at == null) {
      return null;
    }
    if (kind != 'distance' && kind != 'hours') return null;
    final unit = body['unit'] == 'km'
        ? DistanceUnit.km
        : body['unit'] == 'mi'
        ? DistanceUnit.mi
        : null;
    if ((kind == 'distance' && unit == null) ||
        (kind == 'hours' && body['unit'] != null)) {
      return null;
    }
    return MaintenanceReading(
      id: id,
      assetId: parent,
      value: value,
      scale: scale,
      kind: kind == 'distance' ? MeterKind.distance : MeterKind.hours,
      unit: unit,
      at: at.toUtc(),
      corrected: body['corrected'] == true,
    );
  }
}
