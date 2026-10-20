import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_people.dart';
import 'money_format.dart';
import 'module.dart';

/// What is still out in one direction, in each currency by itself — a sum
/// across currencies would need a rate nobody has entered — with the
/// overdue count said plainly beside it.
class LoanSummaryCard extends StatelessWidget {
  const LoanSummaryCard({
    super.key,
    required this.summary,
    required this.owedToMe,
  });

  final LoanSummary summary;

  /// True for the Lent tab ("owed to me"), false for Borrowed ("I owe").
  final bool owedToMe;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final persian = NexModuleStrings.persian(context);
    final lines = <String>[
      for (final total in summary.money)
        formatMoney(total.minor, total.currency, total.digits, persian),
      if (summary.itemsOut > 0)
        strings(context, 'itemsOut', {'n': summary.itemsOut}),
    ];
    // The first amount leads, large; the other currencies, items and the
    // overdue count follow as small facts. Colour: Lent and Borrowed are one
    // module, so one hue; direction is said by the icon and the title.
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
