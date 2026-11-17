import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_people.dart';
import 'module.dart';
import 'money_format.dart';

/// What a set of records adds up to, in the units a person reads: one line
/// per currency — never a sum across currencies, which would need a rate
/// nobody has entered — and the count of items still out.
List<String> summaryAmountLines(
  BuildContext context,
  LoanSummary summary,
  IrrUnit unit,
) {
  final strings = lentStrings;
  final persian = NexModuleStrings.persian(context);
  return [
    for (final total in summary.money)
      formatAmount(total.minor, total.currency, total.digits, persian, unit),
    if (summary.itemsOut > 0)
      strings(context, summary.itemsOut == 1 ? 'itemsOut1' : 'itemsOut', {
        'n': summary.itemsOut,
      }),
  ];
}

/// The direction's total, in the module's hero: the first amount leads,
/// large; the other currencies, items and the overdue count follow as small
/// facts. Lent and Borrowed are one module, so one hue; the direction is
/// said by the icon and the eyebrow.
class LoanSummaryCard extends StatelessWidget {
  const LoanSummaryCard({
    super.key,
    required this.summary,
    required this.owedToMe,
    required this.unit,
  });

  final LoanSummary summary;

  /// True for the Lent tab ("owed to me"), false for Borrowed ("I owe").
  final bool owedToMe;
  final IrrUnit unit;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final lines = summaryAmountLines(context, summary, unit);
    return NexModuleHero(
      key: const ValueKey('loans-summary'),
      moduleId: 'lent_borrowed',
      icon: owedToMe ? Icons.south_west : Icons.north_east,
      eyebrow: strings(context, owedToMe ? 'owedToMe' : 'iOwe'),
      headline: lines.isEmpty ? strings(context, 'nothingOut') : lines.first,
      chips: [
        ...lines.skip(1),
        if (summary.overdue > 0)
          strings(context, 'overdueCount', {'n': summary.overdue}),
      ],
    );
  }
}
