import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'home.dart';
import 'privacy.dart';
import 'reminders.dart';
import 'strings.dart';
import 'dues.dart';
import 'glance.dart';

class ChequeManagerModule extends NexStoredModule {
  const ChequeManagerModule();
  @override
  String get id => 'cheques';
  @override
  IconData get icon => Icons.receipt_long_outlined;
  @override
  NexHue get hue => NexHue.sky;
  @override
  NexModuleStrings get strings => chequeStrings;
  @override
  Widget screen(NexModuleStore store) =>
      ChequePrivacy(child: ChequeHome(store: store));
  @override
  Future<void> keepUp(NexModuleStore store, AppLocalizations l10n) =>
      renewCheques(store, l10n);

  @override
  Future<List<ModuleDue>> dues(
    NexModuleStore store,
    DateTime from,
    DateTime to,
  ) async => ChequeDues.fromRecords([
    ...await store.list('cheque'),
    ...await store.list('plan'),
  ]).duesBetween(from, to);

  @override
  Future<ModuleGlance?> glance(
    NexModuleStore store,
    AppLocalizations l10n,
    DateTime now,
  ) => chequeGlance(store, l10n, now);
}
