import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/converter/converter_size_tables.dart';
import 'package:nex_client/modules/converter/converter_sizes.dart';

SizeChart chart(String id) => converterSizeChartById(id)!;

SizeRow rowWith(SizeChart chart, String systemId, String size) =>
    chart.rows.firstWhere((row) => row.sizeIn(systemId) == size);

double measure(SizeRow row, String key) =>
    row.measures.firstWhere((entry) => entry.key == key).value;

void main() {
  group('the charts', () {
    test('every chart names a system for every row', () {
      expect(converterSizeCharts, hasLength(8));
      for (final value in converterSizeCharts) {
        expect(value.systems, isNotEmpty, reason: value.id);
        for (final system in value.systems) {
          for (final row in value.rows) {
            expect(
              row.sizeIn(system.id),
              isNotNull,
              reason: '${value.id} has no ${system.id} in a row',
            );
          }
        }
      }
    });

    test(
      'every row carries a measurement, and every measurement is positive',
      () {
        for (final value in converterSizeCharts) {
          for (final row in value.rows) {
            expect(row.measures, isNotEmpty, reason: value.id);
            for (final entry in row.measures) {
              expect(entry.value, greaterThan(0), reason: value.id);
            }
          }
        }
      },
    );

    test('the ring letters only ever go up', () {
      final rings = chart('rings');
      var previous = 0.0;
      for (final row in rings.rows) {
        final circumference = measure(row, 'circumference');
        expect(circumference, greaterThan(previous));
        previous = circumference;
      }
      expect(rings.rows, hasLength(41));
    });
  });

  group("women's and men's clothing", () {
    test('the European number and the body it is cut for', () {
      final tops = chart('womenTops');
      final thirtyEight = rowWith(tops, 'eu', '38');
      expect(tops.rows.first.sizeIn('eu'), '34');
      expect(tops.rows.last.sizeIn('eu'), '52');
      expect(measure(thirtyEight, 'bust'), 88);
      expect(measure(thirtyEight, 'waist'), 76);
      expect(measure(thirtyEight, 'hip'), 100);
      expect(thirtyEight.sizeIn('uk'), '10');
      expect(thirtyEight.sizeIn('us'), '6');
      expect(thirtyEight.sizeIn('iran'), '38');
    });

    test("men's jacket numbers are the chest in inches", () {
      final tops = chart('menTops');
      final fortyEight = rowWith(tops, 'eu', '48');
      expect(measure(fortyEight, 'chest'), 96);
      expect(fortyEight.sizeIn('uk'), '38');
      expect(fortyEight.sizeIn('us'), '38');
      expect(fortyEight.sizeIn('iran'), '48');
    });

    test("men's trouser numbers are the waist in inches", () {
      final trousers = chart('menTrousers');
      final fortyEight = rowWith(trousers, 'eu', '48');
      expect(measure(fortyEight, 'waist'), 84);
      expect(fortyEight.sizeIn('uk'), '33');
      expect(fortyEight.sizeIn('us'), '33');
    });
  });

  group('shoes', () {
    test('a 27 cm foot, in every system', () {
      final women = chart('womenShoes');
      final teens = rowWith(women, 'foot', '27');
      expect(teens.sizeIn('eu'), '42.5');
      expect(teens.sizeIn('uk'), '9');
      expect(teens.sizeIn('us'), '11');
      expect(teens.sizeIn('iran'), '43.5');
      expect(measure(teens, 'foot'), 27);

      final men = chart('menShoes');
      final sameFoot = rowWith(men, 'foot', '27');
      expect(sameFoot.sizeIn('eu'), '42.5');
      expect(sameFoot.sizeIn('us'), '10');
      expect(sameFoot.sizeIn('iran'), '43.5');
    });

    test("children's sizes stay inside the children's block", () {
      final children = chart('childrenShoes');
      expect(children.rows.first.sizeIn('eu'), '16');
      expect(children.rows.last.sizeIn('eu'), '30');
      expect(children.rows.first.sizeIn('uk'), '0');
      expect(children.rows.first.sizeIn('us'), '1');
      expect(measure(children.rows.first, 'foot'), 8.1);
    });
  });

  group('rings', () {
    test('F is 43.75 mm around, and its neighbours follow the rule', () {
      final rings = chart('rings');
      final f = rowWith(rings, 'uk', 'F');
      expect(f.sizeIn('iso'), '43.75');
      expect(measure(f, 'circumference'), 43.75);
      expect(measure(f, 'diameter'), closeTo(13.93, 0.01));
      expect(f.sizeIn('iran'), '39');
      expect(f.sizeIn('us'), '2.75');

      final fHalf = rowWith(rings, 'uk', 'F½');
      expect(measure(fHalf, 'circumference'), 44.375);
      final g = rowWith(rings, 'uk', 'G');
      expect(measure(g, 'circumference'), 45);
    });

    test('the Iranian shop number is the circumference less five', () {
      final rings = chart('rings');
      for (final row in rings.rows) {
        final circumference = measure(row, 'circumference');
        expect(
          int.parse(row.sizeIn('iran')!),
          (circumference - 5).round(),
          reason: row.sizeIn('uk'),
        );
      }
    });
  });

  group('showing a size', () {
    test('digits follow the reader, the letter does not', () {
      expect(converterShowSize('36.5', persian: false), '36.5');
      expect(converterShowSize('36.5', persian: true), '۳۶٫۵');
      expect(converterShowSize('F½', persian: true), 'F½');
      expect(converterShowSize('10', persian: true), '۱۰');
    });

    test('a chart that is gone answers null, not a crash', () {
      expect(converterSizeChartById('hats'), isNull);
      expect(converterSizeChartById(''), isNull);
    });
  });
}
