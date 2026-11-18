import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'security_home.dart';
import 'security_strings.dart';
import 'security_glance.dart';

class SecurityToolsModule extends NexStoredModule {
  const SecurityToolsModule();
  @override
  String get id => 'security_tools';
  @override
  IconData get icon => Icons.shield_outlined;
  @override
  NexHue get hue => NexHue.sky;
  @override
  NexModuleStrings get strings => securityStrings;
  @override
  Widget screen(NexModuleStore store) => SecurityHome(store: store);

  @override
  Future<ModuleGlance?> glance(
    NexModuleStore store,
    AppLocalizations l10n,
    DateTime now,
  ) => securityGlance(store, l10n, now);
}
