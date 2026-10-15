import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/maintenance/logic.dart';
import 'package:nex_client/modules/maintenance/models.dart';
import 'package:nex_client/modules/maintenance/units.dart';

/// The due computation and grouping: what each rule resolves to from
/// real records, and every unknown said out loud.
part 'logic_cases_1.dart';
part 'logic_cases_2.dart';

final now = DateTime(2026, 10, 13);

MaintenanceAsset asset({
  String id = 'car',
  MeterKind meter = MeterKind.distance,
  DistanceUnit unit = DistanceUnit.km,
  DateTime? purchased,
  bool archived = false,
}) => MaintenanceAsset(
  id: id,
  nickname: 'Car',
  type: 'car',
  meterKind: meter,
  distanceUnit: unit,
  purchasedAt: purchased,
  archived: archived,
);

ServiceEvent event(
  String id,
  DateTime date, {
  String assetId = 'car',
  String task = 'oil change',
  int? meter,
  DistanceUnit? meterUnit,
  int? cost,
  String? currency,
}) => ServiceEvent(
  id: id,
  assetId: assetId,
  date: date,
  task: task,
  meter: meter,
  meterUnit: meterUnit,
  cost: cost,
  currency: currency,
);

IntervalRule rule({
  String assetId = 'car',
  String task = 'oil change',
  int? days,
  int? months,
  int? meters,
  int? hours,
  DistanceUnit? meterUnit,
}) => IntervalRule(
  id: 'rule-1',
  assetId: assetId,
  task: task,
  days: days,
  months: months,
  meters: meters,
  hours: hours,
  meterUnit: meterUnit,
);

void main() {
  _logicCases1();
  _logicCases2();
}
