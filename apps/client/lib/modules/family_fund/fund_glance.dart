import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'strings.dart';

/// The pinned tile and quick view of the family fund (2.8.5): this month's
/// contributions paid out of those due, and whether the draw is done, on
/// the tile; each fund's month, balance and winner in the quick view.
Future<ModuleGlance?> fundGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      fundStrings.text(l10n, key, args);
  final funds = (await store.list('fund')).map(Fund.read).nonNulls.toList();
  if (funds.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  final month = fundMonth(now);
  var due = 0, paid = 0, drawn = 0;
  final facts = <ModuleGlanceFact>[];
  for (final fund in funds) {
    final active = month.first.isBefore(fund.start.first)
        ? const <Fields>[]
        : fund.active(month);
    final done = active.where((m) => fund.payment(month, m['id']) != null);
    due += active.length;
    paid += done.length;
    final winner = fund.winner(month);
    if (winner != null) drawn++;
    facts
      ..add(
        ModuleGlanceFact(
          fund.name,
          t('glancePaidOf', {'paid': done.length, 'total': active.length}),
          strong: true,
        ),
      )
      ..add(
        ModuleGlanceFact(
          t('glanceBalance'),
          nexTomanText(BigInt.from(fund.balanceAt(now)), l10n),
        ),
      )
      ..add(
        ModuleGlanceFact(
          t('glanceDraw'),
          winner == null ? t('glanceNotDrawn') : t('glanceDrawn'),
        ),
      );
  }
  return ModuleGlance(
    headline: t('glancePaidOf', {'paid': paid, 'total': due}),
    detail: drawn == funds.length ? t('glanceDrawn') : t('glanceNotDrawn'),
    progress: due == 0 ? null : paid / due,
    facts: facts,
  );
}
