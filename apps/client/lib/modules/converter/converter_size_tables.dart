import 'dart:math' as math;

import 'converter_sizes.dart';

/// The tables themselves. Every number in this file comes from a source named
/// in the module README; nothing here is estimated by eye.

const _clothingSystems = [
  SizeSystem('eu', 'sysEu'),
  SizeSystem('uk', 'sysUk'),
  SizeSystem('us', 'sysUs'),
  SizeSystem('iran', 'sysIran'),
];

const _shoeSystems = [
  SizeSystem('eu', 'sysEu'),
  SizeSystem('uk', 'sysUk'),
  SizeSystem('us', 'sysUs'),
  SizeSystem('iran', 'sysIran'),
  SizeSystem('foot', 'sysFoot'),
];

const _ringSystems = [
  SizeSystem('iso', 'sysIso'),
  SizeSystem('uk', 'sysUk'),
  SizeSystem('us', 'sysUs'),
  SizeSystem('iran', 'sysIran'),
];

/// Women's tops: the European number and the body it is cut for (EN 13402-3
/// body measurements, 4 cm bust steps), with the British and American dress
/// numbers and the same European number Iranian shops sell.
const converterClothingCharts = <SizeChart>[
  SizeChart(
    id: 'womenTops',
    titleKey: 'chartWomenTops',
    noteKey: 'chartNoteClothingIran',
    systems: _clothingSystems,
    rows: [
      SizeRow(
        sizes: {'eu': '34', 'uk': '6', 'us': '2', 'iran': '34'},
        measures: [
          SizeMeasure('bust', 80),
          SizeMeasure('waist', 68),
          SizeMeasure('hip', 92),
        ],
      ),
      SizeRow(
        sizes: {'eu': '36', 'uk': '8', 'us': '4', 'iran': '36'},
        measures: [
          SizeMeasure('bust', 84),
          SizeMeasure('waist', 72),
          SizeMeasure('hip', 96),
        ],
      ),
      SizeRow(
        sizes: {'eu': '38', 'uk': '10', 'us': '6', 'iran': '38'},
        measures: [
          SizeMeasure('bust', 88),
          SizeMeasure('waist', 76),
          SizeMeasure('hip', 100),
        ],
      ),
      SizeRow(
        sizes: {'eu': '40', 'uk': '12', 'us': '8', 'iran': '40'},
        measures: [
          SizeMeasure('bust', 92),
          SizeMeasure('waist', 80),
          SizeMeasure('hip', 104),
        ],
      ),
      SizeRow(
        sizes: {'eu': '42', 'uk': '14', 'us': '10', 'iran': '42'},
        measures: [
          SizeMeasure('bust', 96),
          SizeMeasure('waist', 84),
          SizeMeasure('hip', 108),
        ],
      ),
      SizeRow(
        sizes: {'eu': '44', 'uk': '16', 'us': '12', 'iran': '44'},
        measures: [
          SizeMeasure('bust', 100),
          SizeMeasure('waist', 88),
          SizeMeasure('hip', 112),
        ],
      ),
      SizeRow(
        sizes: {'eu': '46', 'uk': '18', 'us': '14', 'iran': '46'},
        measures: [
          SizeMeasure('bust', 104),
          SizeMeasure('waist', 94),
          SizeMeasure('hip', 117),
        ],
      ),
      SizeRow(
        sizes: {'eu': '48', 'uk': '20', 'us': '16', 'iran': '48'},
        measures: [
          SizeMeasure('bust', 110),
          SizeMeasure('waist', 100),
          SizeMeasure('hip', 122),
        ],
      ),
      SizeRow(
        sizes: {'eu': '50', 'uk': '22', 'us': '18', 'iran': '50'},
        measures: [
          SizeMeasure('bust', 116),
          SizeMeasure('waist', 106),
          SizeMeasure('hip', 127),
        ],
      ),
      SizeRow(
        sizes: {'eu': '52', 'uk': '24', 'us': '20', 'iran': '52'},
        measures: [
          SizeMeasure('bust', 122),
          SizeMeasure('waist', 112),
          SizeMeasure('hip', 132),
        ],
      ),
    ],
  ),
  SizeChart(
    id: 'womenTrousers',
    titleKey: 'chartWomenTrousers',
    noteKey: 'chartNoteClothingIran',
    systems: _clothingSystems,
    rows: [
      SizeRow(
        sizes: {'eu': '34', 'uk': '6', 'us': '2', 'iran': '34'},
        measures: [SizeMeasure('waist', 68), SizeMeasure('hip', 92)],
      ),
      SizeRow(
        sizes: {'eu': '36', 'uk': '8', 'us': '4', 'iran': '36'},
        measures: [SizeMeasure('waist', 72), SizeMeasure('hip', 96)],
      ),
      SizeRow(
        sizes: {'eu': '38', 'uk': '10', 'us': '6', 'iran': '38'},
        measures: [SizeMeasure('waist', 76), SizeMeasure('hip', 100)],
      ),
      SizeRow(
        sizes: {'eu': '40', 'uk': '12', 'us': '8', 'iran': '40'},
        measures: [SizeMeasure('waist', 80), SizeMeasure('hip', 104)],
      ),
      SizeRow(
        sizes: {'eu': '42', 'uk': '14', 'us': '10', 'iran': '42'},
        measures: [SizeMeasure('waist', 84), SizeMeasure('hip', 108)],
      ),
      SizeRow(
        sizes: {'eu': '44', 'uk': '16', 'us': '12', 'iran': '44'},
        measures: [SizeMeasure('waist', 88), SizeMeasure('hip', 112)],
      ),
      SizeRow(
        sizes: {'eu': '46', 'uk': '18', 'us': '14', 'iran': '46'},
        measures: [SizeMeasure('waist', 94), SizeMeasure('hip', 117)],
      ),
      SizeRow(
        sizes: {'eu': '48', 'uk': '20', 'us': '16', 'iran': '48'},
        measures: [SizeMeasure('waist', 100), SizeMeasure('hip', 122)],
      ),
      SizeRow(
        sizes: {'eu': '50', 'uk': '22', 'us': '18', 'iran': '50'},
        measures: [SizeMeasure('waist', 106), SizeMeasure('hip', 127)],
      ),
      SizeRow(
        sizes: {'eu': '52', 'uk': '24', 'us': '20', 'iran': '52'},
        measures: [SizeMeasure('waist', 112), SizeMeasure('hip', 132)],
      ),
    ],
  ),
  // Men's jackets: the same European number as the chest, and the British and
  // American number that is that chest in inches — which is why the two
  // columns agree with each other and not with the dress sizes above.
  SizeChart(
    id: 'menTops',
    titleKey: 'chartMenTops',
    noteKey: 'chartNoteMenUkUs',
    systems: _clothingSystems,
    rows: [
      SizeRow(
        sizes: {'eu': '44', 'uk': '34', 'us': '34', 'iran': '44'},
        measures: [SizeMeasure('chest', 88), SizeMeasure('waist', 76)],
      ),
      SizeRow(
        sizes: {'eu': '46', 'uk': '36', 'us': '36', 'iran': '46'},
        measures: [SizeMeasure('chest', 92), SizeMeasure('waist', 80)],
      ),
      SizeRow(
        sizes: {'eu': '48', 'uk': '38', 'us': '38', 'iran': '48'},
        measures: [SizeMeasure('chest', 96), SizeMeasure('waist', 84)],
      ),
      SizeRow(
        sizes: {'eu': '50', 'uk': '40', 'us': '40', 'iran': '50'},
        measures: [SizeMeasure('chest', 100), SizeMeasure('waist', 88)],
      ),
      SizeRow(
        sizes: {'eu': '52', 'uk': '42', 'us': '42', 'iran': '52'},
        measures: [SizeMeasure('chest', 104), SizeMeasure('waist', 92)],
      ),
      SizeRow(
        sizes: {'eu': '54', 'uk': '44', 'us': '44', 'iran': '54'},
        measures: [SizeMeasure('chest', 108), SizeMeasure('waist', 96)],
      ),
      SizeRow(
        sizes: {'eu': '56', 'uk': '46', 'us': '46', 'iran': '56'},
        measures: [SizeMeasure('chest', 112), SizeMeasure('waist', 100)],
      ),
      SizeRow(
        sizes: {'eu': '58', 'uk': '48', 'us': '48', 'iran': '58'},
        measures: [SizeMeasure('chest', 116), SizeMeasure('waist', 104)],
      ),
    ],
  ),
  // Men's trousers: the number is the waist in centimetres; the British and
  // American one is the same waist in inches, which is what a pair of jeans
  // is labelled with.
  SizeChart(
    id: 'menTrousers',
    titleKey: 'chartMenTrousers',
    noteKey: 'chartNoteTrouserInches',
    systems: _clothingSystems,
    rows: [
      SizeRow(
        sizes: {'eu': '44', 'uk': '30', 'us': '30', 'iran': '44'},
        measures: [SizeMeasure('waist', 76), SizeMeasure('hip', 96)],
      ),
      SizeRow(
        sizes: {'eu': '46', 'uk': '31', 'us': '31', 'iran': '46'},
        measures: [SizeMeasure('waist', 80), SizeMeasure('hip', 100)],
      ),
      SizeRow(
        sizes: {'eu': '48', 'uk': '33', 'us': '33', 'iran': '48'},
        measures: [SizeMeasure('waist', 84), SizeMeasure('hip', 104)],
      ),
      SizeRow(
        sizes: {'eu': '50', 'uk': '35', 'us': '35', 'iran': '50'},
        measures: [SizeMeasure('waist', 88), SizeMeasure('hip', 108)],
      ),
      SizeRow(
        sizes: {'eu': '52', 'uk': '36', 'us': '36', 'iran': '52'},
        measures: [SizeMeasure('waist', 92), SizeMeasure('hip', 112)],
      ),
      SizeRow(
        sizes: {'eu': '54', 'uk': '38', 'us': '38', 'iran': '54'},
        measures: [SizeMeasure('waist', 96), SizeMeasure('hip', 116)],
      ),
      SizeRow(
        sizes: {'eu': '56', 'uk': '39', 'us': '39', 'iran': '56'},
        measures: [SizeMeasure('waist', 100), SizeMeasure('hip', 120)],
      ),
      SizeRow(
        sizes: {'eu': '58', 'uk': '41', 'us': '41', 'iran': '58'},
        measures: [SizeMeasure('waist', 104), SizeMeasure('hip', 124)],
      ),
    ],
  ),
];

/// ISO 19407's adult conversion between foot length and the three systems
/// people actually read on a box. Foot length is the bare foot; a shoe adds
/// roughly 10 mm of ease, which is already inside these numbers.
const _adultFeet =
    <({int millimetres, String eu, String uk, String usMen, String usWomen})>[
      (millimetres: 215, eu: '34', uk: '2', usMen: '3', usWomen: '4'),
      (millimetres: 220, eu: '35', uk: '3', usMen: '4', usWomen: '5'),
      (millimetres: 225, eu: '35.5', uk: '3.5', usMen: '4.5', usWomen: '5.5'),
      (millimetres: 230, eu: '36.5', uk: '4', usMen: '5', usWomen: '6'),
      (millimetres: 235, eu: '37', uk: '4.5', usMen: '5.5', usWomen: '6.5'),
      (millimetres: 240, eu: '38', uk: '5.5', usMen: '6.5', usWomen: '7.5'),
      (millimetres: 245, eu: '38.5', uk: '6', usMen: '7', usWomen: '8'),
      (millimetres: 250, eu: '39.5', uk: '6.5', usMen: '7.5', usWomen: '8.5'),
      (millimetres: 255, eu: '40', uk: '7', usMen: '8', usWomen: '9'),
      (millimetres: 260, eu: '41', uk: '7.5', usMen: '8.5', usWomen: '9.5'),
      (millimetres: 265, eu: '41.5', uk: '8.5', usMen: '9.5', usWomen: '10.5'),
      (millimetres: 270, eu: '42.5', uk: '9', usMen: '10', usWomen: '11'),
      (millimetres: 275, eu: '43', uk: '9.5', usMen: '10.5', usWomen: '11.5'),
      (millimetres: 280, eu: '44', uk: '10', usMen: '11', usWomen: '12'),
      (
        millimetres: 285,
        eu: '44.5',
        uk: '10.5',
        usMen: '11.5',
        usWomen: '12.5',
      ),
      (millimetres: 290, eu: '45.5', uk: '11', usMen: '12', usWomen: '13'),
      (millimetres: 295, eu: '46', uk: '12', usMen: '13', usWomen: '14'),
      (millimetres: 300, eu: '47', uk: '12.5', usMen: '13.5', usWomen: '14.5'),
    ];

/// Children's shoes, up to the point where the British and American scales
/// restart at 1. Above this, a child's foot is an adult size and the chart
/// above is the one to read.
const _childrenFeet = <({int millimetres, String eu, String uk, String us})>[
  (millimetres: 81, eu: '16', uk: '0', us: '1'),
  (millimetres: 90, eu: '17', uk: '1', us: '2'),
  (millimetres: 98, eu: '18', uk: '2', us: '3'),
  (millimetres: 106, eu: '19', uk: '3', us: '4'),
  (millimetres: 115, eu: '20', uk: '4', us: '5'),
  (millimetres: 128, eu: '22', uk: '5.5', us: '6'),
  (millimetres: 140, eu: '24', uk: '7', us: '7.5'),
  (millimetres: 153, eu: '26', uk: '8.5', us: '9'),
  (millimetres: 166, eu: '28', uk: '10', us: '10.5'),
  (millimetres: 178, eu: '30', uk: '11.5', us: '12'),
];

/// Women's, men's and children's shoes.
final List<SizeChart> converterShoeCharts = [
  SizeChart(
    id: 'womenShoes',
    titleKey: 'chartWomenShoes',
    noteKey: 'chartNoteShoes',
    systems: _shoeSystems,
    rows: [
      for (final foot in _adultFeet)
        SizeRow(
          sizes: {
            'eu': foot.eu,
            'uk': foot.uk,
            'us': foot.usWomen,
            'iran': _plusOne(foot.eu),
            'foot': _centimetres(foot.millimetres),
          },
          measures: [SizeMeasure('foot', foot.millimetres / 10)],
        ),
    ],
  ),
  SizeChart(
    id: 'menShoes',
    titleKey: 'chartMenShoes',
    noteKey: 'chartNoteShoes',
    systems: _shoeSystems,
    rows: [
      for (final foot in _adultFeet)
        SizeRow(
          sizes: {
            'eu': foot.eu,
            'uk': foot.uk,
            'us': foot.usMen,
            'iran': _plusOne(foot.eu),
            'foot': _centimetres(foot.millimetres),
          },
          measures: [SizeMeasure('foot', foot.millimetres / 10)],
        ),
    ],
  ),
  SizeChart(
    id: 'childrenShoes',
    titleKey: 'chartChildrenShoes',
    noteKey: 'chartNoteChildren',
    systems: _shoeSystems,
    rows: [
      for (final foot in _childrenFeet)
        SizeRow(
          sizes: {
            'eu': foot.eu,
            'uk': foot.uk,
            'us': foot.us,
            'iran': _plusOne(foot.eu),
            'foot': _centimetres(foot.millimetres),
          },
          measures: [SizeMeasure('foot', foot.millimetres / 10)],
        ),
    ],
  ),
];

/// Every chart, in the picker's order: clothing, shoes, rings.
final List<SizeChart> converterSizeCharts = [
  ...converterClothingCharts,
  ...converterShoeCharts,
  _ringChart(),
];

/// The chart [id], or null when a stored record names one this version no
/// longer has.
SizeChart? converterSizeChartById(String id) {
  for (final chart in converterSizeCharts) {
    if (chart.id == id) return chart;
  }
  return null;
}

/// Rings, built from the two published rules rather than a copied list: the
/// British letter series of BS 6820 (A = 37.5 mm inner circumference, 1.25 mm
/// per letter) and ISO 8653's inner circumference in millimetres, with the US
/// number and the Iranian shop number that both follow from it.
SizeChart _ringChart() {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final rows = <SizeRow>[];
  for (var index = 5; index <= 25; index++) {
    for (final half in const [false, true]) {
      // There is no half size past the last letter.
      if (half && index == 25) continue;
      final circumference = 37.5 + 1.25 * index + (half ? 0.625 : 0);
      final us = ((circumference - 36.54) / 2.55 * 4).round() / 4;
      rows.add(
        SizeRow(
          sizes: {
            'iso': _trim(circumference),
            'uk': '${letters[index]}${half ? '½' : ''}',
            'us': _trim(us),
            // Iranian jewellers sell on the inner circumference less five.
            'iran': '${(circumference - 5).round()}',
          },
          measures: [
            SizeMeasure('circumference', circumference, unit: SizeUnit.mm),
            SizeMeasure('diameter', circumference / math.pi, unit: SizeUnit.mm),
          ],
        ),
      );
    }
  }
  return SizeChart(
    id: 'rings',
    titleKey: 'chartRings',
    noteKey: 'chartNoteRings',
    systems: _ringSystems,
    rows: rows,
  );
}

String _plusOne(String label) {
  final value = double.tryParse(label);
  return value == null ? label : _trim(value + 1);
}

String _centimetres(int millimetres) => _trim(millimetres / 10);

String _trim(double value) {
  var text = value.toStringAsFixed(2);
  if (text.contains('.')) {
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  return text;
}
