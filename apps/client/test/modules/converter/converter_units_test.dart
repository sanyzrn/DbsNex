import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/converter/converter_units.dart';

double? convert(UnitCategory category, String from, String to, double value) =>
    converterConvertUnit(
      category: category,
      fromId: from,
      toId: to,
      value: value,
    );

void main() {
  group('the definitions the standards give', () {
    test('length, from the 1959 international yard', () {
      expect(
        convert(UnitCategory.length, 'inch', 'cm', 1),
        closeTo(2.54, 1e-12),
      );
      expect(
        convert(UnitCategory.length, 'foot', 'cm', 1),
        closeTo(30.48, 1e-12),
      );
      expect(
        convert(UnitCategory.length, 'yard', 'cm', 1),
        closeTo(91.44, 1e-12),
      );
      expect(
        convert(UnitCategory.length, 'mile', 'km', 1),
        closeTo(1.609344, 1e-12),
      );
      expect(
        convert(UnitCategory.length, 'nauticalMile', 'm', 1),
        closeTo(1852, 1e-12),
      );
      expect(
        convert(UnitCategory.length, 'foot', 'inch', 1),
        closeTo(12, 1e-12),
      );
      expect(
        convert(UnitCategory.length, 'mile', 'foot', 1),
        closeTo(5280, 1e-9),
      );
    });

    test('mass, from the international pound', () {
      expect(
        convert(UnitCategory.mass, 'pound', 'kg', 1),
        closeTo(0.45359237, 1e-12),
      );
      expect(
        convert(UnitCategory.mass, 'ounce', 'g', 1),
        closeTo(28.349523125, 1e-9),
      );
      expect(
        convert(UnitCategory.mass, 'pound', 'ounce', 1),
        closeTo(16, 1e-12),
      );
      expect(
        convert(UnitCategory.mass, 'tonne', 'kg', 1),
        closeTo(1000, 1e-12),
      );
      expect(
        convert(UnitCategory.mass, 'kg', 'pound', 1),
        closeTo(2.2046226218, 1e-9),
      );
    });

    test('volume: the US gallon is 231 cubic inches, the imperial is not', () {
      expect(
        convert(UnitCategory.volume, 'usGallon', 'l', 1),
        closeTo(3.785411784, 1e-12),
      );
      expect(
        convert(UnitCategory.volume, 'ukGallon', 'l', 1),
        closeTo(4.54609, 1e-12),
      );
      expect(
        convert(UnitCategory.volume, 'usGallon', 'usFluidOunce', 1),
        closeTo(128, 1e-9),
      );
      expect(
        convert(UnitCategory.volume, 'usCup', 'usFluidOunce', 1),
        closeTo(8, 1e-12),
      );
      expect(
        convert(UnitCategory.volume, 'usCup', 'ml', 1),
        closeTo(236.5882365, 1e-9),
      );
      expect(convert(UnitCategory.volume, 'l', 'ml', 1), closeTo(1000, 1e-9));
    });

    test('area and speed', () {
      expect(
        convert(UnitCategory.area, 'hectare', 'm2', 1),
        closeTo(10000, 1e-9),
      );
      expect(
        convert(UnitCategory.area, 'acre', 'm2', 1),
        closeTo(4046.8564224, 1e-9),
      );
      expect(
        convert(UnitCategory.area, 'ft2', 'm2', 1),
        closeTo(0.09290304, 1e-12),
      );
      expect(
        convert(UnitCategory.area, 'acre', 'ft2', 1),
        closeTo(43560, 1e-6),
      );
      expect(
        convert(UnitCategory.speed, 'knot', 'kmh', 1),
        closeTo(1.852, 1e-12),
      );
      expect(
        convert(UnitCategory.speed, 'mph', 'kmh', 1),
        closeTo(1.609344, 1e-12),
      );
      expect(convert(UnitCategory.speed, 'ms', 'kmh', 1), closeTo(3.6, 1e-12));
      expect(
        convert(UnitCategory.speed, 'knot', 'mph', 1),
        closeTo(1.150779448, 1e-9),
      );
    });

    test('temperature goes through Celsius, not a multiplication', () {
      expect(convert(UnitCategory.temperature, 'celsius', 'fahrenheit', 0), 32);
      expect(
        convert(UnitCategory.temperature, 'celsius', 'fahrenheit', 100),
        212,
      );
      expect(
        convert(UnitCategory.temperature, 'celsius', 'fahrenheit', -40),
        -40,
      );
      expect(convert(UnitCategory.temperature, 'fahrenheit', 'celsius', 32), 0);
      expect(convert(UnitCategory.temperature, 'celsius', 'kelvin', 0), 273.15);
      expect(
        convert(UnitCategory.temperature, 'kelvin', 'celsius', 0),
        -273.15,
      );
      expect(
        convert(UnitCategory.temperature, 'kelvin', 'fahrenheit', 273.15),
        32,
      );
      expect(converterUnderAbsoluteZero('celsius', -300), isTrue);
      expect(converterUnderAbsoluteZero('celsius', -273.15), isFalse);
      expect(converterUnderAbsoluteZero('kelvin', 0), isFalse);
      expect(converterUnderAbsoluteZero('fahrenheit', -500), isTrue);
    });
  });

  group('the Iranian units, at the value the README names', () {
    test('mass', () {
      expect(
        convert(UnitCategory.mass, 'mesghal', 'g', 1),
        closeTo(4.608, 1e-12),
      );
      expect(convert(UnitCategory.mass, 'sir', 'g', 1), closeTo(75, 1e-12));
      expect(
        convert(UnitCategory.mass, 'manTabriz', 'kg', 1),
        closeTo(3, 1e-12),
      );
      expect(
        convert(UnitCategory.mass, 'kharvar', 'kg', 1),
        closeTo(300, 1e-12),
      );
      expect(
        convert(UnitCategory.mass, 'kharvar', 'manTabriz', 1),
        closeTo(100, 1e-12),
      );
    });

    test('length', () {
      expect(convert(UnitCategory.length, 'zar', 'cm', 1), closeTo(104, 1e-12));
      expect(
        convert(UnitCategory.length, 'gazShahi', 'cm', 1),
        closeTo(112, 1e-12),
      );
    });

    test('each of them is marked approximate, with a note', () {
      for (final unit in converterUnits) {
        if (unit.approximate) {
          expect(unit.noteKey, isNotNull, reason: unit.id);
        }
      }
      expect(converterUnitById('mesghal')!.approximate, isTrue);
      expect(converterUnitById('kg')!.approximate, isFalse);
    });
  });

  group('the lists', () {
    test('every unit has a unique id and belongs to one category', () {
      final ids = converterUnits.map((unit) => unit.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final unit in converterUnits) {
        if (unit.category != UnitCategory.temperature) {
          expect(unit.factor, isNotNull, reason: unit.id);
          expect(unit.factor, greaterThan(0), reason: unit.id);
        } else {
          expect(unit.factor, isNull, reason: unit.id);
        }
      }
    });

    test('every category opens with a pair of its own units', () {
      for (final category in UnitCategory.values) {
        final pair = converterDefaultPair(category);
        expect(converterUnitById(pair.from)!.category, category);
        expect(converterUnitById(pair.to)!.category, category);
        expect(
          converterUnitsIn(category),
          hasLength(greaterThanOrEqualTo(3)),
          reason: category.name,
        );
      }
    });

    test('nothing converts across a category or from a unit that is gone', () {
      expect(convert(UnitCategory.length, 'kg', 'metre', 1), isNull);
      expect(convert(UnitCategory.mass, 'kilogram', 'pound', 1), isNull);
      expect(convert(UnitCategory.mass, 'kg', 'pound', 0), 0);
      expect(converterUnitById('lightyear'), isNull);
    });

    test('a conversion and back returns the number it started with', () {
      for (final category in UnitCategory.values) {
        final pair = converterDefaultPair(category);
        for (final value in [0.0, 1.0, 12.5, 999.0]) {
          final there = convert(category, pair.from, pair.to, value)!;
          final back = convert(category, pair.to, pair.from, there)!;
          expect(back, closeTo(value, 1e-9), reason: '${category.name} $value');
        }
      }
    });
  });
}
