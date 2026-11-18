library;

import 'units.dart';
import 'local_values.dart';
import 'costs.dart';
part 'asset_model.dart';
part 'event_model.dart';
part 'rule_model.dart';
part 'reading_model.dart';
part 'fuel_model.dart';

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

/// The lead time a car's insurance and inspection reminders use until the
/// person changes it.
const defaultCarLeadDays = 14;

String? _stringOf(Map<String, Object?> body, String key) {
  final value = body[key];
  return value is String ? value : null;
}
