import 'package:nex_client/modules/module_api.dart';

import 'prompt_model.dart';
import 'studio_strings.dart';

/// The pinned tile and quick view of Prompt Studio (2.8.5): how many
/// prompts are kept and the favourites in the quick view.
Future<ModuleGlance?> studioGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      studioStrings.text(l10n, key, args);
  final entries = (await store.list('entry'))
      .map(PromptEntry.fromRecord)
      .where((e) => e.valid)
      .toList();
  final prompts = entries.where((e) => !e.block).toList();
  if (prompts.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  final favorites = prompts.where((e) => e.favorite).toList();
  return ModuleGlance(
    headline: t('glancePrompts', {'n': prompts.length}),
    detail: favorites.isEmpty
        ? null
        : t('glanceFavorites', {'n': favorites.length}),
    facts: [
      for (final e in (favorites.isEmpty ? prompts : favorites).take(6))
        ModuleGlanceFact(
          e.title,
          e.category.isEmpty ? '' : e.category,
          strong: e.favorite,
        ),
    ],
  );
}
