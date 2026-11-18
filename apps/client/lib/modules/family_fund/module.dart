import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'reminder_upkeep.dart';
import 'screen.dart';
import 'strings.dart';
import 'model.dart';
import 'projection.dart';

export 'strings.dart';

class FamilyFundModule extends NexStoredModule {
  const FamilyFundModule();
  @override
  String get id => 'family_fund';
  @override
  IconData get icon => Icons.groups_outlined;
  @override
  NexHue get hue => NexHue.teal;
  @override
  NexModuleStrings get strings => fundStrings;
  @override
  Widget screen(NexModuleStore store) => FamilyFundsScreen(store: store);

  /// The manager's alerts come round every month (2.8.4).
  @override
  Future<void> keepUp(NexModuleStore store, AppLocalizations l10n) =>
      FundReminderUpkeep.roll(store, l10n);

  @override
  Future<List<ModuleDue>> dues(
    NexModuleStore store,
    DateTime from,
    DateTime to,
  ) async => [
    for (final fund in (await store.list('fund')).map(Fund.read).nonNulls)
      ...FundDues(fund).duesBetween(from, to),
  ]..sort((a, b) => a.at.compareTo(b.at));
}
