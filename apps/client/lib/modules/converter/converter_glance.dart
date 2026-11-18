import 'package:nex_client/modules/module_api.dart';

import 'converter_strings.dart';

/// The pinned tile of the Converter (2.8.5): how many conversions are kept
/// under Recent and Starred.
Future<ModuleGlance?> converterGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      converterStrings.text(l10n, key, args);
  final recent = (await store.list('recent')).length;
  final starred = (await store.list('favorite')).length;
  if (recent + starred == 0) return ModuleGlance(headline: t('glanceEmpty'));
  return ModuleGlance(
    headline: t('glanceStarred', {'n': starred}),
    detail: t('glanceRecent', {'n': recent}),
  );
}
