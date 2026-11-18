import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'screen.dart';
import 'strings.dart';

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
}
