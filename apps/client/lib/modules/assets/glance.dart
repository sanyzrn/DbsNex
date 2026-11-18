import 'package:nex_client/modules/module_api.dart';

import 'strings.dart';

/// The pinned tile of the Asset book (2.8.5) keeps the book covered: no
/// amount, name or count is read for the home screen or the quick view.
Future<ModuleGlance?> assetsGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async => ModuleGlance(
  headline: assetStrings.text(l10n, 'privateTitle'),
  detail: assetStrings.text(l10n, 'glanceOpen'),
);
