import 'local_values.dart';

/// Where I parked — one folder, the module API and nothing else.
///
/// The record kinds, calculations and honest limits are documented in
/// `README.md`. Nothing in this module reaches past its `NexModuleStore`: no
/// location sensor, no camera, no notifications and no network.
class ParkingModels {
  const ParkingModels._();

  /// Record kind: one parking session, open or closed.
  static const session = 'session';

  /// Record kind: a remembered place, for parking the same spot again.
  static const place = 'place';

  /// Record kind: one recent search query.
  static const search = 'search';

  /// How many recent queries are kept.
  static const searchHistoryLimit = 8;

  /// A latitude is valid between these.
  static const latMin = -90.0;
  static const latMax = 90.0;

  /// A longitude is valid between these.
  static const lngMin = -180.0;
  static const lngMax = 180.0;

  // ------------------------------------------------------------- readers

  /// A string field, or '' when it is missing or not a string. Old records
  /// with absent fields must keep opening.
  static String readString(Map<String, Object?> body, String key) {
    final value = body[key];
    return value is String ? value : '';
  }

  /// A stored ISO 8601 timestamp, or null when missing or unparsable.
  static DateTime? readDate(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! String) {
      return null;
    }
    return LocalValues.stamp(value);
  }

  /// A manually typed coordinate, or null when missing, unparsable or
  /// outside its range. A coordinate that fails the range check is *wrong*,
  /// not rounded into place.
  static double? readCoord(
    Map<String, Object?> body,
    String key, {
    required double min,
    required double max,
  }) {
    final value = body[key];
    if (value is! num) {
      return null;
    }
    final asDouble = value.toDouble();
    if (!asDouble.isFinite || asDouble < min || asDouble > max) {
      return null;
    }
    return asDouble;
  }

  /// A non-negative integer field, or null when missing or invalid.
  static int? readCount(Map<String, Object?> body, String key) {
    final value = body[key];
    return LocalValues.count(value);
  }

  // -------------------------------------------------------------- session

  /// The body of a parking session. [startedAt] is when it was recorded and
  /// [foundAt] null while the car is still parked there.
  static Map<String, Object?> sessionBody({
    required String vehicle,
    required String place,
    required String floor,
    required String spot,
    required String landmark,
    required DateTime startedAt,
    DateTime? foundAt,
    DateTime? expiresAt,
    double? lat,
    double? lng,
  }) => {
    'v': 1,
    'vehicle': vehicle.trim(),
    'place': place.trim(),
    'floor': floor.trim(),
    'spot': spot.trim(),
    'landmark': landmark,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (foundAt != null) 'foundAt': foundAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
  };

  /// The body of a remembered place.
  static Map<String, Object?> placeBody({
    required String place,
    required String floor,
    required String spot,
    required String landmark,
    required int useCount,
    required DateTime lastUsedAt,
    double? lat,
    double? lng,
  }) => {
    'v': 1,
    'place': place.trim(),
    'floor': floor.trim(),
    'spot': spot.trim(),
    'landmark': landmark,
    'useCount': useCount,
    'lastUsedAt': lastUsedAt.toUtc().toIso8601String(),
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
  };

  /// The body of a remembered search query.
  static Map<String, Object?> searchBody({
    required String query,
    required DateTime at,
  }) => {'v': 1, 'query': query.trim(), 'at': at.toUtc().toIso8601String()};

  /// Case and folded whitespace match; there is no transliteration.
  static bool sameVehicle(String a, String b) =>
      _vehicleKey(a) == _vehicleKey(b);
  static String _vehicleKey(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
