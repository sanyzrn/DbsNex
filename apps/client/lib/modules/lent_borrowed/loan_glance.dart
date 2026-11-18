import 'package:nex_client/modules/module_api.dart';

import 'loan_math.dart';
import 'loan_model.dart';
import 'module.dart' show lentStrings;

/// The pinned tile and quick view of Lent & Borrowed (2.8.5): how many are
/// open or late on the tile, never a name or an amount; what is owed each
/// way, in rials, in the quick view.
Future<ModuleGlance?> loanGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  final loans = (await store.list('loan')).map(Loan.fromRecord).toList();
  final returns = (await store.list('return'))
      .map(LoanReturn.fromRecord)
      .toList();
  String t(String key, [Map<String, Object?> args = const {}]) =>
      lentStrings.text(l10n, key, args);
  final standings = LoanMath.standingsOf(loans, returns, today: now);
  final open = [
    for (final loan in loans)
      if (standings[loan.id] case final s? when !s.settled) (loan, s),
  ];
  if (open.isEmpty) return ModuleGlance(headline: t('glanceNone'));
  final late = open.where((e) => e.$2.due.status == DueStatus.overdue).length;
  final lent = open.where((e) => e.$1.direction == LoanDirection.lent).length;
  final owedToMe = BigInt.from(
    open
        .where(
          (e) =>
              e.$1.direction == LoanDirection.lent &&
              e.$1.kind == LoanKind.money &&
              e.$1.currency == 'IRR',
        )
        .fold(0, (sum, e) => sum + e.$2.outstanding),
  );
  final iOwe = BigInt.from(
    open
        .where(
          (e) =>
              e.$1.direction == LoanDirection.borrowed &&
              e.$1.kind == LoanKind.money &&
              e.$1.currency == 'IRR',
        )
        .fold(0, (sum, e) => sum + e.$2.outstanding),
  );
  return ModuleGlance(
    headline: late > 0
        ? t('glanceLate', {'n': late})
        : t('glanceOpen', {'n': open.length}),
    detail: t('glanceSides', {'lent': lent, 'borrowed': open.length - lent}),
    facts: [
      ModuleGlanceFact(
        t('glanceOwedToMe'),
        nexTomanText(owedToMe, l10n),
        strong: true,
      ),
      ModuleGlanceFact(t('glanceIOwe'), nexTomanText(iOwe, l10n)),
      ModuleGlanceFact(
        t('glanceItems'),
        nexDigits(
          '${open.where((e) => e.$1.kind == LoanKind.item).length}',
          persian: l10n.localeName.startsWith('fa'),
        ),
      ),
    ],
  );
}
