import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'strings.dart';

/// The pinned tile and quick view of the family fund (2.8.5): this month's
/// contributions paid out of those due, and whether the draw is done, on
/// the tile; each fund's month, balance and winner in the quick view.
///
/// A fund that has not started yet has no contribution to count, so it is
/// left out of the tile's fraction and says when it starts instead of
/// reporting «0 of 0».
Future<ModuleGlance?> fundGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      fundStrings.text(l10n, key, args);
  final persian = l10n.localeName.startsWith('fa');
  final funds = (await store.list('fund')).map(Fund.read).nonNulls.toList()
    ..sort((a, b) {
      final byStart = a.start.first.compareTo(b.start.first);
      return byStart != 0 ? byStart : a.name.compareTo(b.name);
    });
  if (funds.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  final month = fundMonth(now);
  var due = 0, paid = 0, drawn = 0;
  final started = <Fund>[];
  final facts = <ModuleGlanceFact>[];
  for (final fund in funds) {
    final active = month.first.isBefore(fund.start.first)
        ? const <Fields>[]
        : fund.active(month);
    final hasStarted = !month.first.isBefore(fund.start.first);
    if (hasStarted) started.add(fund);
    final done = active.where((m) => fund.payment(month, m['id']) != null);
    due += active.length;
    paid += done.length;
    final winner = fund.winner(month);
    if (hasStarted && winner != null) drawn++;
    facts.add(
      ModuleGlanceFact(
        fund.name,
        hasStarted
            ? t('glancePaidOf', {'paid': done.length, 'total': active.length})
            : t('glanceUpcoming', {
                'date': nexReadableDate(
                  fund.start.first,
                  solar: true,
                  persian: persian,
                ),
              }),
        strong: true,
      ),
    );
    if (hasStarted) {
      facts.add(
        ModuleGlanceFact(
          t('glanceBalance'),
          nexTomanText(BigInt.from(fund.balanceAt(now)), l10n),
        ),
      );
      facts.add(
        ModuleGlanceFact(
          t('glanceDraw'),
          winner == null ? t('glanceNotDrawn') : t('glanceDrawn'),
        ),
      );
    }
  }
  final nextStart = funds
      .where((fund) => month.first.isBefore(fund.start.first))
      .map((fund) => fund.start)
      .firstOrNull;
  return ModuleGlance(
    headline: due > 0
        ? t('glancePaidOf', {'paid': paid, 'total': due})
        : started.isEmpty && nextStart != null
        ? t('glanceUpcoming', {
            'date': nexReadableDate(
              nextStart.first,
              solar: true,
              persian: persian,
            ),
          })
        : t('glanceNoMembers'),
    detail: started.isEmpty
        ? t('fundsCount', {'n': funds.length})
        : drawn == started.length
        ? t('glanceDrawn')
        : t('glanceNotDrawn'),
    progress: due == 0 ? null : paid / due,
    facts: facts,
  );
}
