import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'privacy.dart';
import 'dues.dart';
import 'strings.dart';
import 'widgets.dart';

class ChequeMonth extends StatelessWidget {
  const ChequeMonth({
    super.key,
    required this.rows,
    required this.month,
    required this.move,
    required this.open,
  });
  final List<Cheque> rows;
  final DateTime month;
  final ValueChanged<int> move;
  final ValueChanged<Cheque> open;
  @override
  Widget build(BuildContext context) {
    final p = nexPersianDate(month),
        start = nexGregorianDate(p.year, p.month, 1),
        end = p.month == 12
            ? nexGregorianDate(p.year + 1, 1, 1)
            : nexGregorianDate(p.year, p.month + 1, 1);
    final dues = ChequeDues(rows)
        .duesBetween(start, DateTime(end.year, end.month, end.day - 1))
        .where((d) => !d.done && d.kind != 'cheque-review')
        .toList();
    final byId = {
      for (final c in rows) c.recordKind == 'plan' ? c.id : 'cheque:${c.id}': c,
    };
    final byDay = <DateTime, List<Cheque>>{};
    for (final due in dues) {
      (byDay[due.at] ??= []).add(byId[due.id]!);
    }
    final selected = byDay.values.expand((items) => items);
    final hidden = chequeHidden(context);
    BigInt sum(Iterable<Cheque> xs, String dir) => xs
        .where((c) => c.direction == dir)
        .fold(BigInt.zero, (v, c) => v + c.remaining);
    final outgoing = sum(selected, 'outgoing'),
        incoming = sum(selected, 'incoming'),
        net = incoming - outgoing,
        s = chequeStrings;
    return ListView(
      padding: const EdgeInsets.all(NexSpacing.md),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: s(context, 'previousMonth'),
              onPressed: () => move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                nexModuleDateLabel(context, start),
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: s(context, 'nextMonth'),
              onPressed: () => move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        NexPanel(
          title: s(context, 'month'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${s(context, 'outgoingTotal')}: ${chequeMoney(context, outgoing)} ${s(context, 'toman')}',
              ),
              Text(
                '${s(context, 'incomingTotal')}: ${chequeMoney(context, incoming)} ${s(context, 'toman')}',
              ),
              Text(
                '${s(context, 'net')}: ${!hidden && net < BigInt.zero ? '−' : ''}${chequeMoney(context, net.abs())} ${s(context, 'toman')}',
              ),
              Text(s(context, 'netHint')),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        // Only the days something falls due (2.8.4): a card for every day
        // of the month, most of them "nothing due", buried the few that
        // matter. A day more goes out than comes in is marked.
        if (byDay.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NexSpacing.lg),
            child: Text(
              s(context, 'noCommitments'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final MapEntry(key: date, value: items) in byDay.entries)
          Builder(
            builder: (c) {
              final deficit =
                  !hidden && sum(items, 'outgoing') > sum(items, 'incoming');
              final scheme = Theme.of(c).colorScheme;
              return Padding(
                key: ValueKey('cheque-month-day-$date'),
                padding: const EdgeInsets.only(bottom: NexSpacing.sm),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(NexRadius.lg),
                    border: deficit
                        ? Border.all(color: scheme.error.withValues(alpha: 0.6))
                        : null,
                  ),
                  child: NexPanel(
                    title: nexModuleDateLabel(context, date),
                    icon: deficit
                        ? Icons.south_east
                        : Icons.calendar_today_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (deficit)
                          Text(
                            s(context, 'moreOut'),
                            style: TextStyle(
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        for (final item in items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.party),
                            subtitle: Text(
                              '${s(context, item.direction)} · ${chequeMoney(context, item.remaining)} ${s(context, 'toman')}',
                            ),
                            onTap: () => open(item),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: kMinInteractiveDimension * 2),
      ],
    );
  }
}
