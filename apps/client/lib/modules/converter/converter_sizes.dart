/// The size charts: clothing, shoes and rings, with the measurement each size
/// stands for.
///
/// A size number on its own means nothing — a 38 is a different body in
/// Milan, Manchester and Tehran — so every row here carries the body
/// measurement the number is based on, and the screen always shows it beside
/// the size. The sources of each table are in the module's README.
library;

import 'package:nex_client/modules/module_api.dart';

/// What a measurement is in. Clothing and foot length are centimetres; rings
/// are millimetres.
enum SizeUnit { cm, mm }

class SizeMeasure {
  const SizeMeasure(this.key, this.value, {this.unit = SizeUnit.cm});

  /// `bust`, `waist`, `hip`, `chest`, `foot`, `circumference`, `diameter` —
  /// the module's strings have a word for each.
  final String key;
  final double value;
  final SizeUnit unit;
}

/// One line of a chart: the same body, named in each system.
class SizeRow {
  const SizeRow({required this.sizes, required this.measures});

  /// System id → the size printed on a label, as digits and letters only.
  final Map<String, String> sizes;
  final List<SizeMeasure> measures;

  String? sizeIn(String systemId) => sizes[systemId];
}

class SizeSystem {
  const SizeSystem(this.id, this.labelKey);

  final String id;

  /// A word in the module's strings, so the column is named in both
  /// languages.
  final String labelKey;
}

class SizeChart {
  const SizeChart({
    required this.id,
    required this.titleKey,
    required this.systems,
    required this.rows,
    this.noteKey,
  });

  final String id;
  final String titleKey;

  /// One line under the chart: what is peculiar to it — that Iranian shops
  /// use the European number, or that children's numbering restarts.
  final String? noteKey;
  final List<SizeSystem> systems;
  final List<SizeRow> rows;
}

/// [label] as a person reads it — «۳۶٫۵» in Persian, «36.5» in English.
String converterShowSize(String label, {required bool persian}) {
  if (!persian) return label;
  return nexDigits(label.replaceAll('.', '\u066B'), persian: true);
}
