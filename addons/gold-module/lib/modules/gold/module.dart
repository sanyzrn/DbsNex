import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_screen.dart';
import 'gold_strings.dart';

/// «Gold Check» — an auditable calculator for new gold jewelry in Iran.
///
/// Everything a person needs to question a counter price honestly: the
/// weight, fineness and rate they were given, the making-charge formula
/// the shop uses, an editable profit and VAT, and a line-by-line receipt
/// that keeps entered numbers apart from calculated ones. Saved estimates
/// keep the rates of their own day.
class GoldModule extends NexStoredModule {
  const GoldModule();

  @override
  String get id => 'gold';

  @override
  IconData get icon => Icons.diamond_outlined;

  @override
  NexHue get hue => NexHue.amber;

  @override
  NexModuleStrings get strings => goldStrings;

  @override
  Widget screen(NexModuleStore store) => GoldScreen(store: store);
}
