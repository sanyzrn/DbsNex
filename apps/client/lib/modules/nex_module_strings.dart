import 'package:flutter/widgets.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;

import '../l10n/app_localizations.dart';

/// A module's words, in both languages, kept inside the module.
///
/// The app's own words live in its ARB files; a module's live with it, so a
/// module is one folder that can be added or taken out without touching
/// anything else. Both maps must hold the same keys — the module kit's test
/// checks — and these keys are required: `title`, `tagline`, `about`, and
/// `point1` to `point4` (at least two).
///
/// `{name}` in a value is filled from the arguments. Numbers given as
/// arguments are written in Persian digits on the Persian side.
class NexModuleStrings {
  const NexModuleStrings({required this.en, required this.fa});

  final Map<String, String> en;
  final Map<String, String> fa;

  /// [key] in the language [l10n] is in.
  String text(
    AppLocalizations l10n,
    String key, [
    Map<String, Object?> args = const {},
  ]) {
    final persian = l10n.localeName.startsWith('fa');
    var value = (persian ? fa : en)[key] ?? en[key] ?? key;
    for (final MapEntry(:key, value: arg) in args.entries) {
      final shown = arg is num
          ? nexDigits('$arg', persian: persian)
          : '${arg ?? ''}';
      value = value.replaceAll('{$key}', shown);
    }
    return value;
  }

  /// [key] in the language the app is showing — `strings(context, 'save')`.
  String call(
    BuildContext context,
    String key, [
    Map<String, Object?> args = const {},
  ]) => text(AppLocalizations.of(context), key, args);

  /// Whether the app is showing Persian — for the few things words alone do
  /// not cover, like which calendar a date is written in.
  static bool persian(BuildContext context) =>
      AppLocalizations.of(context).localeName.startsWith('fa');
}
