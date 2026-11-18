import 'package:nex_client/modules/module_api.dart';

import 'account_model.dart';
import 'security_strings.dart';

/// The pinned tile and quick view of the Security toolbox (2.8.5): how many
/// accounts still have a step to take; each account's checks done in the
/// quick view — never a password, which the toolbox never keeps.
Future<ModuleGlance?> securityGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      securityStrings.text(l10n, key, args);
  final accounts = (await store.list('account'))
      .map(SecurityAccount.fromRecord)
      .where((a) => a.valid)
      .toList();
  if (accounts.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  final open = accounts.where((a) => a.next != null).length;
  final total = securityChecks.length;
  final done = accounts.fold(0, (sum, a) => sum + a.done);
  return ModuleGlance(
    headline: open == 0 ? t('glanceAllDone') : t('glanceOpen', {'n': open}),
    detail: t('glanceAccounts', {'n': accounts.length}),
    progress: done / (accounts.length * total),
    facts: [
      for (final a in accounts)
        ModuleGlanceFact(
          a.label,
          t('glanceChecks', {'done': a.done, 'total': total}),
          strong: a.next != null,
        ),
    ],
  );
}
