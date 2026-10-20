/// Measurement units for the Price Lens, with the exact rational
/// factor each one carries relative to its family's base (grams,
/// millilitres, pieces). Nothing is approximated: the conversions are
/// the legal definitions, held as fractions.
///
/// Mass and volume are different families and are never compared
/// without a density the person entered (v1 disallows it outright —
/// see the README's Decisions). US fluid ounces are named
/// unambiguously and converted exactly; imperial units beyond that
/// are simply not offered rather than half-labelled.
library;

import 'rational.dart';

/// A family of comparable units.
enum UnitFamily { mass, volume, piece }

/// One unit a quantity can be entered in.
class PriceUnit {
  const PriceUnit(this.key, this.family, this.factorToBase, this.decimals);

  /// The stable key, also the strings key for its name.
  final String key;

  final UnitFamily family;

  /// How many base units (g / ml / pieces) one of this unit is.
  final Fraction factorToBase;

  /// How many decimals make sense when a person types this unit —
  /// gram quantities are whole; litres come in 0.75.
  final int decimals;

  bool get isBase => factorToBase == const Fraction(1);
}

const gramFactor = Fraction(1);
const kilogramFactor = Fraction(1000);
// 1 lb = 453.59237 g exactly (international avoirdupois); 1 oz = lb/16.
const poundFactor = Fraction(45359237, 100000);
const ounceFactor = Fraction(45359237, 1600000);
// 1 US fl oz = 29.5735295625 ml exactly (1 US gallon = 3785.411784 ml).
const usFlOzFactor = Fraction(473176473, 16000000);
const litreFactor = Fraction(1000);
const millilitreFactor = Fraction(1);
const pieceFactor = Fraction(1);

/// Every unit the module knows, in display order.
const priceUnits = <PriceUnit>[
  PriceUnit('g', UnitFamily.mass, gramFactor, 3),
  PriceUnit('g100', UnitFamily.mass, Fraction(100), 3),
  PriceUnit('kg', UnitFamily.mass, kilogramFactor, 3),
  PriceUnit('oz', UnitFamily.mass, ounceFactor, 3),
  PriceUnit('lb', UnitFamily.mass, poundFactor, 3),
  PriceUnit('ml', UnitFamily.volume, millilitreFactor, 3),
  PriceUnit('ml100', UnitFamily.volume, Fraction(100), 3),
  PriceUnit('l', UnitFamily.volume, litreFactor, 3),
  PriceUnit('floz', UnitFamily.volume, usFlOzFactor, 3),
  PriceUnit('piece', UnitFamily.piece, pieceFactor, 0),
];

PriceUnit? priceUnitOf(String? key) {
  if (key == null) return null;
  for (final unit in priceUnits) {
    if (unit.key == key) return unit;
  }
  return null;
}

/// The units of [family], for the common-unit picker.
List<PriceUnit> unitsOfFamily(UnitFamily family) => [
  for (final unit in priceUnits)
    if (unit.family == family) unit,
];

/// The canonical comparison unit of a family — what the common unit
/// defaults to before the person chooses.
PriceUnit canonicalUnitOf(UnitFamily family) => switch (family) {
  UnitFamily.mass => priceUnitOf('kg')!,
  UnitFamily.volume => priceUnitOf('l')!,
  UnitFamily.piece => priceUnitOf('piece')!,
};

/// Converts a quantity of [from] into [to], exactly — or null when
/// the units are of different families (mass against volume is not a
/// question this module answers by guessing a density).
Fraction? convertQuantity(Fraction quantity, PriceUnit from, PriceUnit to) {
  if (from.family != to.family) return null;
  if (from.key == to.key) return quantity;
  final inBase = quantity * from.factorToBase;
  return inBase / to.factorToBase;
}

/// The family's base unit — grams for mass, millilitres for volume.
PriceUnit baseUnitOf(UnitFamily family) => switch (family) {
  UnitFamily.mass => priceUnitOf('g')!,
  UnitFamily.volume => priceUnitOf('ml')!,
  UnitFamily.piece => priceUnitOf('piece')!,
};
