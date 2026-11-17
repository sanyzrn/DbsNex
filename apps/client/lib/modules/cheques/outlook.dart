import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'logic.dart';
import 'model.dart';
import 'strings.dart';
import 'widgets.dart';

class ChequeOutlook extends StatelessWidget {
  const ChequeOutlook({
    super.key,
    required this.rows,
    required this.today,
    required this.controller,
    required this.open,
  });
  final List<Cheque> rows;
  final DateTime today;
  final ScrollController controller;
  final ValueChanged<Cheque> open;
  Future<void> _window(BuildContext context, ChequeWindow window) =>
      nexShowSheet<void>(
        context: context,
        builder: (sheet) => SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .7,
          child: ListView(
            padding: const EdgeInsets.all(NexSpacing.md),
            children: [
              Text(
                chequeStrings(sheet, 'windowDetails'),
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              const SizedBox(height: NexSpacing.md),
              if (window.items.isEmpty) Text(chequeStrings(sheet, 'noResults')),
              for (final c in window.items)
                ChequeTile(
                  cheque: c,
                  today: today,
                  onTap: () {
                    Navigator.pop(sheet);
                    open(c);
                  },
                ),
            ],
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final s = chequeStrings, windows = chequeOutlook(rows, today);
    final total = windows.fold(BigInt.zero, (sum, w) => sum + w.outgoing);
    var max = BigInt.one;
    for (final w in windows) {
      if (w.outgoing > max) max = w.outgoing;
      if (w.incoming > max) max = w.incoming;
    }
    Widget bar(String key, BigInt n) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${s(context, key)}: ${chequeMoney(context, n)} ${s(context, 'toman')}',
        ),
        const SizedBox(height: NexSpacing.xs),
        Semantics(
          label:
              '${s(context, key)}: ${chequeMoney(context, n)} ${s(context, 'toman')}',
          child: LinearProgressIndicator(
            value: (n * BigInt.from(10000) ~/ max).toInt() / 10000,
            color: key == 'outgoingTotal'
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.secondary,
          ),
        ),
      ],
    );
    return ListView(
      key: const PageStorageKey('cheque-outlook'),
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.xl + nexBottomInset(context) + kMinInteractiveDimension * 2,
      ),
      children: [
        NexModuleHero(
          moduleId: 'cheques',
          icon: Icons.account_balance_wallet_outlined,
          headline: '${chequeMoney(context, total)} ${s(context, 'toman')}',
          caption: s(context, 'outlookHeadline'),
        ),
        const SizedBox(height: NexSpacing.md),
        Text(s(context, 'outlookHint')),
        const SizedBox(height: NexSpacing.sm),
        Text(s(context, 'pastDueHint')),
        const SizedBox(height: NexSpacing.md),
        for (final w in windows)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.md),
            child: NexPanel(
              title:
                  '${nexModuleDateLabel(context, w.from)} — ${nexModuleDateLabel(context, DateTime(w.to.year, w.to.month, w.to.day - 1))}',
              child: InkWell(
                onTap: () => _window(context, w),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      bar('outgoingTotal', w.outgoing),
                      const SizedBox(height: NexSpacing.md),
                      bar('incomingTotal', w.incoming),
                      TextButton(
                        onPressed: () => _window(context, w),
                        child: Text(s(context, 'windowDetails')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
