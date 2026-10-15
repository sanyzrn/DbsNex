part of 'models.dart';

class MaintenanceAsset {
  MaintenanceAsset({
    required this.id,
    required this.nickname,
    required this.type,
    this.model,
    this.purchasedAt,
    this.notes,
    this.meterKind = MeterKind.none,
    this.distanceUnit = DistanceUnit.km,
    this.archived = false,
    this.valid = true,
    this.source,
  });

  final String id;

  /// What the person calls it. Free text.
  final String nickname;

  /// One of [assetTypeIds]: car, motorcycle, … — the label and glyph
  /// come from the strings; this is a stable key.
  final String type;

  /// Make/model/description, free text.
  final String? model;

  /// When it was bought or installed, if known.
  final DateTime? purchasedAt;

  final String? notes;

  /// What it counts: distance, hours, or nothing.
  final MeterKind meterKind;

  /// The distance unit, when [meterKind] is distance.
  final DistanceUnit distanceUnit;

  /// Archived assets keep their full history but leave the home view.
  final bool archived;

  /// False when the stored body was malformed: listed, fixable,
  /// deletable, never silently counted.
  final bool valid;
  final Map<String, Object?>? source;

  Map<String, Object?> toBody() => {
    'nickname': nickname,
    'type': type,
    if (model != null && model!.isNotEmpty) 'model': model,
    if (purchasedAt != null) 'purchasedAt': purchasedAt!.toIso8601String(),
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    'meterKind': meterKind.name,
    if (meterKind == MeterKind.distance) 'distanceUnit': distanceUnit.name,
    'archived': archived,
    'schema': 2,
  };

  static MaintenanceAsset fromBody(String id, Map<String, Object?> body) {
    var valid = true;
    final nickname = _stringOf(body, 'nickname')?.trim() ?? '';
    if (nickname.isEmpty) valid = false;
    final rawType = _stringOf(body, 'type');
    // An unknown type is incomplete *and* shown as Other: the strings
    // have words for the known seven, nothing else.
    final type = rawType != null && assetTypeIds.contains(rawType)
        ? rawType
        : 'other';
    if (rawType == null || !assetTypeIds.contains(rawType)) valid = false;
    final purchasedRaw = _stringOf(body, 'purchasedAt');
    final purchased = purchasedRaw == null
        ? null
        : maintenanceCalendar(purchasedRaw);
    if (purchasedRaw != null && purchased == null) valid = false;
    final meterName = _stringOf(body, 'meterKind');
    final meterKind = switch (meterName) {
      'distance' => MeterKind.distance,
      'hours' => MeterKind.hours,
      _ => MeterKind.none,
    };
    if (meterName != null &&
        !{'none', 'distance', 'hours'}.contains(meterName)) {
      valid = false;
    }
    final distanceName = _stringOf(body, 'distanceUnit');
    if (meterKind == MeterKind.distance &&
        distanceName != 'km' &&
        distanceName != 'mi') {
      valid = false;
    }
    final distanceUnit = distanceName == 'mi'
        ? DistanceUnit.mi
        : DistanceUnit.km;
    return MaintenanceAsset(
      id: id,
      nickname: nickname.isEmpty ? id : nickname,
      type: type,
      model: _stringOf(body, 'model'),
      purchasedAt: purchased,
      notes: _stringOf(body, 'notes'),
      meterKind: meterKind,
      distanceUnit: distanceUnit,
      archived: body['archived'] == true,
      valid: valid,
      source: Map.of(body),
    );
  }
}
