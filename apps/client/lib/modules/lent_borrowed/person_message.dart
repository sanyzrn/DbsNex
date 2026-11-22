import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_model.dart';
import 'loan_people.dart';
import 'module.dart';
import 'money_format.dart';
import 'payment_cards.dart';
import 'upgrade_strings.dart';

/// A ready-to-send message to one person: what is between you, and the card
/// or IBAN to pay to. Copy is one tap; sharing opens the phone's own sheet,
/// and Nex itself never sends anything.
Future<void> showPersonMessageSheet(
  BuildContext context,
  NexModuleStore store, {
  required String person,
  required IrrUnit unit,
  List<String> balanceLines = const [],
  String? intro,
}) => nexShowSheet<void>(
  context: context,
  builder: (_) => PersonMessageSheet(
    store: store,
    person: person,
    unit: unit,
    balanceLines: balanceLines,
    intro: intro,
  ),
);

class PersonMessageSheet extends StatefulWidget {
  const PersonMessageSheet({
    super.key,
    required this.store,
    required this.person,
    required this.unit,
    this.balanceLines = const [],
    this.intro,
  });

  final NexModuleStore store;
  final String person;
  final IrrUnit unit;
  final List<String> balanceLines;
  final String? intro;

  @override
  State<PersonMessageSheet> createState() => _PersonMessageSheetState();
}

class _PersonMessageSheetState extends State<PersonMessageSheet> {
  String _text = '';
  bool _hasPayment = false;
  bool _loading = true;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The words come from the localisations, so the first build waits until
    // they are reachable.
    if (_started) return;
    _started = true;
    unawaited(_build());
  }

  Future<void> _build() async {
    final lines = widget.balanceLines.isEmpty
        ? await personBalanceLines(
            context,
            widget.store,
            widget.person,
            widget.unit,
          )
        : widget.balanceLines;
    if (!mounted) return;
    final card = await cardForPerson(widget.store, widget.person);
    if (!mounted) return;
    final payment = paymentLines(
      card,
      cardLabel: upgradeWord(context, 'messageCard'),
      ibanLabel: upgradeWord(context, 'messageIban'),
      holderLabel: upgradeWord(context, 'messageHolder'),
    );
    setState(() {
      _text = [
        if (widget.intro != null) widget.intro!,
        ...lines,
        // The card lines arrive with a short heading, so a message that
        // begins with an amount still says what the numbers under it are.
        if (payment.isNotEmpty) ...[
          '',
          upgradeWord(context, 'messagePayTo'),
          ...payment,
        ],
      ].join('\n');
      _hasPayment = payment.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _copy() async {
    final messenger = NexBannerHost.of(context);
    final copied = lentStrings(context, 'messageCopied');
    await nexModuleCopyText(_text);
    messenger?.show(message: copied);
  }

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(NexSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings(context, 'splitMessageTitle', {'person': widget.person}),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.md),
            if (_loading)
              const Center(child: NexInlineSpinner())
            else
              NexTextSurface(
                _text,
                key: const ValueKey('person-message-text'),
                selectable: true,
              ),
            if (!_loading && !_hasPayment) ...[
              const SizedBox(height: NexSpacing.sm),
              Text(
                strings(context, 'messageNoCard'),
                key: const ValueKey('person-message-no-card'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: NexSpacing.md),
            FilledButton.icon(
              key: const ValueKey('person-message-copy'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _loading ? null : () => unawaited(_copy()),
              icon: const Icon(Icons.copy_outlined),
              label: Text(lentStrings(context, 'messageCopy')),
            ),
            const SizedBox(height: NexSpacing.xs),
            TextButton.icon(
              key: const ValueKey('person-message-share'),
              onPressed: _loading
                  ? null
                  : () => unawaited(nexModuleShareText(_text)),
              icon: const Icon(Icons.ios_share),
              label: Text(lentStrings(context, 'messageShare')),
            ),
            const SizedBox(height: NexSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every open line between you and [person], per currency and per direction
/// — the same honesty the People page has: no mixed totals.
Future<List<String>> personBalanceLines(
  BuildContext context,
  NexModuleStore store,
  String person,
  IrrUnit unit,
) async {
  final l10n = AppLocalizations.of(context);
  final persian = NexModuleStrings.persian(context);
  final records = await store.list('loan');
  final returns = (await store.list('return'))
      .map(LoanReturn.fromRecord)
      .toList();
  final mine = [
    for (final record in records.map(Loan.fromRecord))
      if (personKeyOf(record.person) == personKeyOf(person)) record,
  ];
  final owedToMe = LoanSummary.of(
    mine.where((l) => l.direction == LoanDirection.lent),
    returns,
  );
  final iOwe = LoanSummary.of(
    mine.where((l) => l.direction == LoanDirection.borrowed),
    returns,
  );
  return [
    for (final total in owedToMe.money)
      upgradeStrings.text(l10n, 'splitMessageOwed', {
        'amount': formatAmount(
          total.minor,
          total.currency,
          total.digits,
          persian,
          unit,
        ),
      }),
    for (final total in iOwe.money)
      upgradeStrings.text(l10n, 'splitMessageIOwe', {
        'amount': formatAmount(
          total.minor,
          total.currency,
          total.digits,
          persian,
          unit,
        ),
      }),
  ];
}
