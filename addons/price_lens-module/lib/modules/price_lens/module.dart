import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'price_lens_screen.dart';
import 'strings.dart';

/// **Price Lens** — which package is actually cheaper?
///
/// Compares the true unit price of 2 to 4 offers with exact rational
/// arithmetic: multi-packs, buy-N-get-M, one discount applied once,
/// explicitly allocated shipping. Deliberately not a price scraper,
/// not a market-rate oracle, and not a barcode scanner — see the
/// README for the boundaries.
class PriceLensModule extends NexStoredModule {
  const PriceLensModule();

  @override
  String get id => 'price_lens';

  @override
  IconData get icon => Icons.calculate_outlined;

  @override
  NexHue get hue => NexHue.violet;

  @override
  NexModuleStrings get strings => priceLensStrings;

  @override
  Widget screen(NexModuleStore store) => PriceLensScreen(store: store);
}
