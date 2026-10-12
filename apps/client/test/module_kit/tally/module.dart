import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'tally_screen.dart';

/// The module kit's worked example: a tally counter, written the way a
/// module from outside has to be — one folder, the module API and nothing
/// else. It is not shipped; the kit's test adds, uses and removes it.
class TallyModule extends NexStoredModule {
  const TallyModule();

  @override
  String get id => 'tally';

  @override
  IconData get icon => Icons.exposure_plus_1;

  @override
  NexHue get hue => NexHue.teal;

  @override
  NexModuleStrings get strings => tallyStrings;

  @override
  Widget screen(NexModuleStore store) => TallyScreen(store: store);
}

const tallyStrings = NexModuleStrings(
  en: {
    'title': 'Tally',
    'tagline': 'Count anything, one tap at a time',
    'about': 'A counter that remembers when each tap was.',
    'point1': 'One tap',
    'point2': 'Remembers when',
    'count': '{count} so far',
    'add': 'Add one',
  },
  fa: {
    'title': 'شمارنده',
    'tagline': 'هر چیزی را بشمارید، با هر لمس یکی',
    'about': 'شمارنده‌ای که یادش می‌ماند هر لمس کی بود.',
    'point1': 'یک لمس',
    'point2': 'یادش می‌ماند کی',
    'count': 'تا اینجا {count}',
    'add': 'یکی اضافه کن',
  },
);
