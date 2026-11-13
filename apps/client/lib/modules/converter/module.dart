import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_screen.dart';
import 'converter_strings.dart';

/// A converter for the three calendars and the measuring systems a person in
/// Iran meets in a normal week: a Gregorian date on a visa form, a lunar date
/// for a religious occasion, a shoe size on a foreign website, a weight in
/// pounds, a ring size from a Turkish shop. Everything is arithmetic done on
/// the phone; nothing is fetched, and no rate that changes daily is offered.
class ConverterModule extends NexStoredModule {
  const ConverterModule();

  @override
  String get id => 'converter';

  @override
  IconData get icon => Icons.swap_horiz_rounded;

  @override
  NexHue get hue => NexHue.teal;

  @override
  NexModuleStrings get strings => converterStrings;

  @override
  Widget screen(NexModuleStore store) => ConverterScreen(store: store);
}
