part of 'models.dart';

/// One fill-up: when, how many litres, what was paid (rials) and which rate
/// it was bought at. The rate is the person's own word from their rate list,
/// because rates and quotas change by government decision — never a fact the
/// module knows by itself.
class FuelEntry {
  const FuelEntry({
    required this.id,
    required this.assetId,
    required this.date,
    required this.litres,
    required this.priceRial,
    required this.rate,
    this.notes,
    this.source,
  });

  final String id;
  final String assetId;
  final DateTime date;

  /// Litres as integer thousandths, so 42.35 L is 42350.
  final int litres;
  final int priceRial;
  final String rate;
  final String? notes;
  final Map<String, Object?>? source;

  static const scale = 1000;
  static const maxLitres = 200000 * scale;

  Map<String, Object?> toBody() => {
    'schema': 1,
    'assetId': assetId,
    'date': date.toIso8601String(),
    'litres': litres,
    'litres_scale': scale,
    'priceRial': priceRial,
    'rate': rate,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };

  static FuelEntry? fromBody(String id, Map<String, Object?> body) {
    final assetId = _stringOf(body, 'assetId');
    final rate = _stringOf(body, 'rate')?.trim();
    final date = maintenanceCalendar(body['date']);
    final litres = body['litres'];
    final price = body['priceRial'];
    if (assetId == null ||
        assetId.isEmpty ||
        rate == null ||
        rate.isEmpty ||
        date == null ||
        litres is! int ||
        litres <= 0 ||
        litres > maxLitres ||
        price is! int ||
        price < 0 ||
        price > LocalValues.maxExact) {
      return null;
    }
    return FuelEntry(
      id: id,
      assetId: assetId,
      date: date,
      litres: litres,
      priceRial: price,
      rate: rate,
      notes: _stringOf(body, 'notes'),
      source: Map.of(body),
    );
  }
}

/// One rate the person buys at, with the monthly quota they were given at
/// that rate. Both are the person's settings: the module never fetches a
/// price and never calls a rate official.
class FuelRate {
  const FuelRate({
    required this.id,
    required this.assetId,
    required this.name,
    required this.quota,
    this.example = false,
    this.source,
  });

  final String id;
  final String assetId;
  final String name;

  /// The monthly quota in litres as integer thousandths; zero means this
  /// rate has no quota attached.
  final int quota;
  final bool example;
  final Map<String, Object?>? source;

  static const scale = 1000;
  static const maxQuota = 200000 * scale;

  Map<String, Object?> toBody() => {
    'schema': 1,
    'assetId': assetId,
    'name': name.trim(),
    'quota': quota,
    'quota_scale': 1000,
    if (example) 'example': true,
  };

  static FuelRate? fromBody(String id, Map<String, Object?> body) {
    final assetId = _stringOf(body, 'assetId');
    final name = _stringOf(body, 'name')?.trim();
    final quota = body['quota'];
    if (assetId == null ||
        assetId.isEmpty ||
        name == null ||
        name.isEmpty ||
        name.length > 40 ||
        quota is! int ||
        quota < 0 ||
        quota > maxQuota) {
      return null;
    }
    return FuelRate(
      id: id,
      assetId: assetId,
      name: name,
      quota: quota,
      example: body['example'] == true,
      source: Map.of(body),
    );
  }
}
