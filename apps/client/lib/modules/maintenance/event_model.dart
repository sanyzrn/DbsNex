part of 'models.dart';

class ServiceEvent {
  ServiceEvent({
    required this.id,
    required this.assetId,
    required this.date,
    required this.task,
    this.cost,
    this.currency,
    this.meter,
    this.meterUnit,
    this.meterScale = 1,
    this.meterKind,
    this.provider,
    this.notes,
    this.valid = true,
    this.meterValid = true,
    this.source,
  });

  final String id;
  final String assetId;

  /// When the service happened (local calendar date).
  final DateTime date;

  /// What was done, free text ("oil change", "filter").
  final String task;

  /// What it cost, as integer minor units of [currency] — only what
  /// the person entered; costs are never inferred.
  final int? cost;
  final String? currency;

  /// The metre reading at service time: kilometres, miles or running
  /// hours, as an integer in [meterUnit]. The unit is stored per
  /// event, so a later unit change on the asset never silently
  /// reinterprets history.
  final int? meter;
  final DistanceUnit? meterUnit;

  /// Who did the work, free text.
  final int meterScale;
  final MeterKind? meterKind;
  int? get meterMilli => toMeterMilli(meter, meterScale);
  final String? provider;

  final String? notes;

  final bool valid;
  final bool meterValid;
  final Map<String, Object?>? source;

  Map<String, Object?> toBody() => {
    'assetId': assetId,
    'date': date.toIso8601String(),
    'task': task,
    if (cost != null) 'cost': cost,
    if (currency != null) 'currency': currency,
    if (currency != null) ...costMetadata(currency!),
    if (meter != null) 'meter': meter,
    if (meter != null) 'meter_scale': meterScale,
    if (meter != null)
      'meter_kind':
          (meterKind ??
                  (meterUnit == null ? MeterKind.hours : MeterKind.distance))
              .name,
    if (meterUnit != null) 'meterUnit': meterUnit!.name,
    if (provider != null && provider!.isNotEmpty) 'provider': provider,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    'schema': 2,
  };

  static ServiceEvent fromBody(String id, Map<String, Object?> body) {
    var valid = true;
    final assetId = _stringOf(body, 'assetId') ?? '';
    if (assetId.isEmpty) valid = false;
    final task = _stringOf(body, 'task')?.trim() ?? '';
    if (task.isEmpty) valid = false;
    final dateRaw = _stringOf(body, 'date');
    final parsed = dateRaw == null ? null : maintenanceCalendar(dateRaw);
    if (dateRaw == null || parsed == null) valid = false;
    // A date that fails to parse is an incomplete record with a
    // standing-in epoch date — listed, fixable, never silently dated.
    final date = parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
    final cost = body['cost'];
    if (cost != null && cost is! int) valid = false;
    final currency =
        _stringOf(body, 'currency_code') ?? _stringOf(body, 'currency');
    if (cost != null &&
        (cost is! int ||
            cost < 0 ||
            cost > costMax ||
            !costRecordValid(currency, body))) {
      valid = false;
    }
    if (cost != null && currency == null) valid = false;
    final meter = body['meter'];
    final scale = body['meter_scale'] ?? 1;
    if (meter != null &&
        (!validMeterScale(scale) ||
            meter is! int ||
            meter < 0 ||
            meter > meterMax * (scale is int ? scale : 1))) {
      valid = false;
    }
    if (meter != null && (meter is! int || meter < 0)) valid = false;
    final meterUnitName = _stringOf(body, 'meterUnit');
    final meterUnit = switch (meterUnitName) {
      'km' => DistanceUnit.km,
      'mi' => DistanceUnit.mi,
      _ => null,
    };
    final kindName = body['meter_kind'];
    final meterValid =
        meter == null ||
        (meter is int &&
            meter >= 0 &&
            validMeterScale(scale) &&
            meter <= meterMax * (scale as int) &&
            (meterUnitName == null ||
                meterUnitName == 'km' ||
                meterUnitName == 'mi') &&
            (kindName == null ||
                kindName == 'distance' ||
                kindName == 'hours') &&
            (kindName != 'distance' || meterUnit != null) &&
            (kindName != 'hours' || meterUnit == null));
    if (!meterValid) valid = false;
    return ServiceEvent(
      id: id,
      assetId: assetId,
      date: date,
      task: task.isEmpty ? '—' : task,
      cost: cost is int ? cost : null,
      currency: currency,
      meter: meter is int && meter >= 0 ? meter : null,
      meterUnit: meterUnit,
      meterScale: validMeterScale(scale) ? scale as int : 1,
      meterKind: body['meter_kind'] == 'distance'
          ? MeterKind.distance
          : body['meter_kind'] == 'hours'
          ? MeterKind.hours
          : null,
      provider: _stringOf(body, 'provider'),
      notes: _stringOf(body, 'notes'),
      valid: valid,
      meterValid: meterValid,
      source: Map.of(body),
    );
  }
}
