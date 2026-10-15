library;

import 'units.dart';
import 'local_values.dart';
import 'costs.dart';
part 'asset_model.dart';
part 'event_model.dart';
part 'rule_model.dart';
part 'reading_model.dart';

/// The stable asset type keys; their words live in the strings, and
/// the examples in the module's documentation are illustrative —
/// nothing is prefilled as personal data.
const assetTypeIds = <String>[
  'car',
  'motorcycle',
  'ac',
  'boiler',
  'filter',
  'appliance',
  'other',
];

String? _stringOf(Map<String, Object?> body, String key) {
  final value = body[key];
  return value is String ? value : null;
}
