import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'screen.dart';
import 'strings.dart';
import 'glance.dart';
export 'strings.dart';

class AssetsModule extends NexStoredModule {
  const AssetsModule();
  @override
  String get id => 'assets';
  @override
  IconData get icon => Icons.account_balance_wallet_outlined;
  @override
  NexHue get hue => NexHue.teal;
  @override
  NexModuleStrings get strings => assetStrings;
  @override
  Widget screen(NexModuleStore store) => AssetsScreen(store: store);

  @override
  Future<ModuleGlance?> glance(
    NexModuleStore store,
    AppLocalizations l10n,
    DateTime now,
  ) => assetsGlance(store, l10n, now);
}
