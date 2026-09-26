import 'package:nex_core/nex_core.dart';
import '../l10n/app_localizations.dart';

/// Translate only untouched seeded tags; never rename stored user data.
String nexTagLabel(Tag tag, AppLocalizations l10n) {
  if (l10n.localeName != 'fa' || tag.id != stableUuidV5(tag.name)) return tag.name;
  return switch (tag.name) {
    'Idea' => 'ایده',
    'Work' => 'کار',
    'Shopping' => 'خرید',
    'Learning' => 'یادگیری',
    'Inspiration' => 'الهام',
    _ => tag.name,
  };
}
