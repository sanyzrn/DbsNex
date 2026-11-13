/// The units the converter knows, and the arithmetic between them.
///
/// Every factor is the exact definition from the standards this module cites
/// in its README — the 1959 international yard and pound (NIST Handbook 44,
/// Appendix C), the imperial gallon of the Weights and Measures Act 1985, the
/// SI's tonne, hectare and kelvin. Values that a traditional Iranian unit
/// only ever had approximately are marked [ConverterUnit.approximate] and
/// carry a note saying which value was used.
library;

enum UnitCategory { length, mass, volume, temperature, area, speed }

class ConverterUnit {
  const ConverterUnit({
    required this.id,
    required this.category,
    this.factor,
    this.noteKey,
    this.approximate = false,
  });

  /// Stable id: keys the record, the labels and the tests.
  final String id;
  final UnitCategory category;

  /// How many of the category's base unit one of these is. Length is metres,
  /// mass kilograms, volume litres, area square metres, speed metres per
  /// second. Temperature is not a multiplication, so it has no factor.
  final double? factor;

  /// The words under the result that say what an approximate unit was taken
  /// to mean, and where the value comes from.
  final String? noteKey;

  /// A unit that varied by region or era — shown with " (approx.)".
  final bool approximate;
}

/// Every unit, in the order the pickers list them: the metric ones, then the
/// imperial/US ones, then the Iranian ones people still meet.
const converterUnits = <ConverterUnit>[
  // ---------------------------------------------------------------- length
  ConverterUnit(id: 'mm', category: UnitCategory.length, factor: 0.001),
  ConverterUnit(id: 'cm', category: UnitCategory.length, factor: 0.01),
  ConverterUnit(id: 'm', category: UnitCategory.length, factor: 1),
  ConverterUnit(id: 'km', category: UnitCategory.length, factor: 1000),
  ConverterUnit(id: 'inch', category: UnitCategory.length, factor: 0.0254),
  ConverterUnit(id: 'foot', category: UnitCategory.length, factor: 0.3048),
  ConverterUnit(id: 'yard', category: UnitCategory.length, factor: 0.9144),
  ConverterUnit(id: 'mile', category: UnitCategory.length, factor: 1609.344),
  ConverterUnit(
    id: 'nauticalMile',
    category: UnitCategory.length,
    factor: 1852,
  ),
  ConverterUnit(
    id: 'zar',
    category: UnitCategory.length,
    factor: 1.04,
    approximate: true,
    noteKey: 'unitNote_zar',
  ),
  ConverterUnit(
    id: 'gazShahi',
    category: UnitCategory.length,
    factor: 1.12,
    approximate: true,
    noteKey: 'unitNote_gazShahi',
  ),

  // ------------------------------------------------------------------ mass
  ConverterUnit(id: 'g', category: UnitCategory.mass, factor: 0.001),
  ConverterUnit(id: 'kg', category: UnitCategory.mass, factor: 1),
  ConverterUnit(id: 'tonne', category: UnitCategory.mass, factor: 1000),
  ConverterUnit(
    id: 'ounce',
    category: UnitCategory.mass,
    factor: 0.028349523125,
  ),
  ConverterUnit(id: 'pound', category: UnitCategory.mass, factor: 0.45359237),
  ConverterUnit(
    id: 'mesghal',
    category: UnitCategory.mass,
    factor: 0.004608,
    approximate: true,
    noteKey: 'unitNote_mesghal',
  ),
  ConverterUnit(
    id: 'sir',
    category: UnitCategory.mass,
    factor: 0.075,
    approximate: true,
    noteKey: 'unitNote_sir',
  ),
  ConverterUnit(
    id: 'manTabriz',
    category: UnitCategory.mass,
    factor: 3,
    approximate: true,
    noteKey: 'unitNote_manTabriz',
  ),
  ConverterUnit(
    id: 'kharvar',
    category: UnitCategory.mass,
    factor: 300,
    approximate: true,
    noteKey: 'unitNote_kharvar',
  ),

  // ---------------------------------------------------------------- volume
  ConverterUnit(id: 'ml', category: UnitCategory.volume, factor: 0.001),
  ConverterUnit(id: 'l', category: UnitCategory.volume, factor: 1),
  ConverterUnit(
    id: 'usGallon',
    category: UnitCategory.volume,
    factor: 3.785411784,
  ),
  ConverterUnit(id: 'ukGallon', category: UnitCategory.volume, factor: 4.54609),
  ConverterUnit(
    id: 'usCup',
    category: UnitCategory.volume,
    factor: 0.2365882365,
  ),
  ConverterUnit(
    id: 'usFluidOunce',
    category: UnitCategory.volume,
    factor: 0.0295735295625,
  ),

  // ----------------------------------------------------------- temperature
  // These three are one-to-one functions of each other, not multiples: the
  // conversion goes through Celsius (see [converterConvertUnit]).
  ConverterUnit(id: 'celsius', category: UnitCategory.temperature),
  ConverterUnit(id: 'fahrenheit', category: UnitCategory.temperature),
  ConverterUnit(id: 'kelvin', category: UnitCategory.temperature),

  // ------------------------------------------------------------------ area
  ConverterUnit(id: 'm2', category: UnitCategory.area, factor: 1),
  ConverterUnit(id: 'hectare', category: UnitCategory.area, factor: 10000),
  ConverterUnit(id: 'acre', category: UnitCategory.area, factor: 4046.8564224),
  ConverterUnit(id: 'ft2', category: UnitCategory.area, factor: 0.09290304),

  // ----------------------------------------------------------------- speed
  ConverterUnit(id: 'ms', category: UnitCategory.speed, factor: 1),
  ConverterUnit(id: 'kmh', category: UnitCategory.speed, factor: 1000 / 3600),
  ConverterUnit(id: 'mph', category: UnitCategory.speed, factor: 0.44704),
  ConverterUnit(id: 'knot', category: UnitCategory.speed, factor: 1852 / 3600),
];

/// Every unit of [category], in listing order.
List<ConverterUnit> converterUnitsIn(UnitCategory category) => [
  for (final unit in converterUnits)
    if (unit.category == category) unit,
];

/// The unit with [id], or null when a stored record names one this version no
/// longer has.
ConverterUnit? converterUnitById(String id) {
  for (final unit in converterUnits) {
    if (unit.id == id) return unit;
  }
  return null;
}

/// The pair a category opens with: a metric unit and the imperial one a
/// person in Iran most often has to compare it with.
({String from, String to}) converterDefaultPair(UnitCategory category) =>
    switch (category) {
      UnitCategory.length => (from: 'm', to: 'foot'),
      UnitCategory.mass => (from: 'kg', to: 'pound'),
      UnitCategory.volume => (from: 'l', to: 'usGallon'),
      UnitCategory.temperature => (from: 'celsius', to: 'fahrenheit'),
      UnitCategory.area => (from: 'm2', to: 'ft2'),
      UnitCategory.speed => (from: 'kmh', to: 'mph'),
    };

/// [value] of [fromId] written in [toId], or null when either unit is not one
/// of this category's.
double? converterConvertUnit({
  required UnitCategory category,
  required String fromId,
  required String toId,
  required double value,
}) {
  if (category == UnitCategory.temperature) {
    final celsius = _toCelsius(fromId, value);
    if (celsius == null) return null;
    return _fromCelsius(toId, celsius);
  }
  final from = converterUnitById(fromId);
  final to = converterUnitById(toId);
  if (from == null || to == null) return null;
  if (from.category != category || to.category != category) return null;
  final fromFactor = from.factor;
  final toFactor = to.factor;
  if (fromFactor == null || toFactor == null || toFactor == 0) return null;
  return value * fromFactor / toFactor;
}

double? _toCelsius(String id, double value) => switch (id) {
  'celsius' => value,
  'fahrenheit' => (value - 32) / 1.8,
  'kelvin' => value - 273.15,
  _ => null,
};

double? _fromCelsius(String id, double celsius) => switch (id) {
  'celsius' => celsius,
  'fahrenheit' => celsius * 1.8 + 32,
  // Below absolute zero is not a temperature. The converter does not hide
  // the number, it just does not pretend it is one: the screen shows the
  // value and the note says it is under absolute zero.
  'kelvin' => celsius + 273.15,
  _ => null,
};

/// Whether [value] is below absolute zero when read in [id] — the one result
/// this module refuses to present as ordinary.
bool converterUnderAbsoluteZero(String id, double value) {
  final celsius = _toCelsius(id, value);
  return celsius != null && celsius < -273.15;
}
