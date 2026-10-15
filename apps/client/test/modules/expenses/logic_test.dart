import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/logic.dart';
import 'package:nex_client/modules/expenses/models.dart';

/// The aggregation and calendar arithmetic: month keys and rollovers,
/// per-currency totals, category breakdowns, budget statuses, filters
/// — all integer, all pure, all defensive.
part 'logic_cases_1.dart';
part 'logic_cases_2.dart';

ExpenseTx tx(
  String id,
  DateTime date, {
  String type = 'expense',
  int amount = 1000,
  String currency = 'IRR',
  String? category = 'cat-food',
  String? note,
  String? merchant,
  String? account,
}) => ExpenseTx(
  id: id,
  type: type,
  amount: amount,
  currency: currency,
  date: date,
  categoryId: category,
  note: note,
  merchant: merchant,
  account: account,
);

void main() {
  _logicCases1();
  _logicCases2();
}
