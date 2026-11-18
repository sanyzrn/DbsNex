import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/assets/model.dart';

ModuleRecord entry(
  String kind,
  String id,
  Fields fields, {
  DateTime? updated,
}) => ModuleRecord(
  module: 'assets',
  kind: kind,
  id: id,
  body: {'v': 1, ...fields},
  updatedAt: updated ?? DateTime(2026, 11, 9),
);

Fields holdingBody(
  AssetMarket market,
  int quantity,
  DateTime day, {
  int price = 1000,
  int fineness = 750,
  String location = '',
}) => {
  ...market.fields,
  'bought': civilDay(day).toIso8601String(),
  if (market.type == AssetType.currency) ...{
    'amount': quantity,
    'currency': market.code,
  } else
    'quantity': quantity,
  'fineness': fineness,
  'costPerUnitRial': price,
  'custody': location.isEmpty ? 'home' : 'platform',
  'location': location,
};

Fields quoteBody(AssetMarket market, int price, DateTime day) => {
  ...market.fields,
  'date': civilDay(day).toIso8601String(),
  'unitRial': price,
};
