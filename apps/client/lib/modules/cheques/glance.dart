import 'package:nex_client/modules/module_api.dart';

import 'dues.dart';
import 'logic.dart';
import 'strings.dart';

/// The pinned tile and quick view of Cheques & instalments (2.8.5): how many
/// are late or due this week on the tile, never an amount; the week's and
/// the month's money in and out in the quick view.
Future<ModuleGlance?> chequeGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  final rows = ChequeDues.fromRecords([
    ...await store.list('cheque'),
    ...await store.list('plan'),
  ]).rows;
  String t(String key, [Map<String, Object?> args = const {}]) =>
      chequeStrings.text(l10n, key, args);
  final open = actionableCheques(rows);
  if (open.isEmpty) return ModuleGlance(headline: t('glanceNone'));
  final today = DateTime(now.year, now.month, now.day);
  final late = open.where((c) => chequeOverdue(c, today)).length;
  final windows = chequeOutlook(rows, today);
  final week = windows.first;
  BigInt out = BigInt.zero, into = BigInt.zero;
  for (final w in windows) {
    out += w.outgoing;
    into += w.incoming;
  }
  final next = open.firstWhere(
    (c) => c.actionDay != null && !chequeOverdue(c, today),
    orElse: () => open.first,
  );
  final nextDay = next.actionDay;
  return ModuleGlance(
    headline: late > 0
        ? t('glanceLate', {'n': late})
        : week.items.isEmpty
        ? t('glanceWeekClear')
        : t('glanceWeek', {'n': week.items.length}),
    detail: nextDay == null
        ? null
        : t('glanceNext', {'when': nexDueWhen(l10n, nextDay, today)}),
    facts: [
      ModuleGlanceFact(
        t('glanceOutWeek'),
        nexTomanText(week.outgoing, l10n),
        strong: true,
      ),
      ModuleGlanceFact(t('glanceInWeek'), nexTomanText(week.incoming, l10n)),
      ModuleGlanceFact(t('glanceOutMonth'), nexTomanText(out, l10n)),
      ModuleGlanceFact(t('glanceInMonth'), nexTomanText(into, l10n)),
      ModuleGlanceFact(t('glanceOpen'), chequeDigitsFor(l10n, open.length)),
    ],
  );
}

String chequeDigitsFor(AppLocalizations l10n, int n) =>
    nexDigits('$n', persian: l10n.localeName.startsWith('fa'));
