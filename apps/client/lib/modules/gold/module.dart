import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_screen.dart';
import 'gold_models.dart';
import 'gold_strings.dart';
import 'gold_glance.dart';

ModuleSummary? summarize(ModuleRecord record) {
  if (record.kind != 'quote') return null;
  final quote = GoldQuote.fromRecord(record.id, record.body);
  return ModuleSummary(
    title: quote.title.isEmpty ? 'Gold estimate' : quote.title,
    private: true,
  );
}

/// «Gold Check» — offline buying, buyback and market conversions for Iran.
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

  @override
  Future<ModuleGlance?> glance(
    NexModuleStore store,
    AppLocalizations l10n,
    DateTime now,
  ) => goldGlance(store, l10n, now);
}
