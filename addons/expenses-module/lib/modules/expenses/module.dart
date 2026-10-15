import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'expenses_screen.dart';
import 'strings.dart';

/// **Expenses** — a voluntary, fully offline book of payments.
///
/// Records a payment in seconds and shows the month without a
/// spreadsheet: totals per currency, a category breakdown, and manual
/// budgets whose arithmetic is on screen. It is deliberately not a
/// bank connection, a finance advisor, a transfer tracker or a
/// duplicate of the notes or Lent & Borrowed modules — see the README
/// for the boundaries and the reasoning.
class ExpensesModule extends NexStoredModule {
  const ExpensesModule();

  @override
  String get id => 'expenses';

  @override
  IconData get icon => Icons.account_balance_wallet_outlined;

  @override
  NexHue get hue => NexHue.teal;

  @override
  NexModuleStrings get strings => expenseStrings;

  @override
  Widget screen(NexModuleStore store) => ExpensesScreen(store: store);
}
