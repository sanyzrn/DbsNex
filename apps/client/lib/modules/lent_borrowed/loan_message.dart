import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_dates.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'money_format.dart';
import 'module.dart';

/// The three ways to say the same thing: a small debt between people, said
/// kindly.
///
/// Persian advice on asking for a debt back (banki.ir, Namnak, Rasekhoon —
/// see the README) agrees on the shape: open warmly, put the awkwardness on
/// yourself rather than on them, and hand them the *timing* — «هر وقت
/// راحت بودی بگو چه زمانی برات مناسبه». Nothing here accuses, reminds them
/// of their duty, or asks twice. The sentences are short on purpose: a long
/// message reads as a demand.
enum MessageTone { friendly, neutral, formal }

/// The message [tone] for [loan], ready to paste. Nothing is sent by Nex:
/// the person copies it, or hands it to the phone's own share sheet.
String loanMessage(
  BuildContext context,
  Loan loan,
  LoanStanding standing,
  IrrUnit unit,
  MessageTone tone,
) {
  final strings = lentStrings;
  final persian = NexModuleStrings.persian(context);
  final person = loan.person.trim().isEmpty
      ? strings(context, 'untitledPerson')
      : loan.person.trim();
  final what = loan.kind == LoanKind.money
      ? formatAmount(
          standing.outstanding,
          loan.currency,
          loan.digits,
          persian,
          unit,
        )
      : _itemPhrase(context, loan, standing, persian);
  final due = loan.due == null ? null : parseCivilDate(loan.due!);
  final clause = due == null
      ? ''
      : strings(context, 'messageDue', {
          'date': nexModuleDateLabel(context, due),
        });
  return strings(context, 'message_${tone.name}', {
    'person': person,
    'amount': what,
    'due': clause,
  });
}

/// «دو عدد کوله‌پشتی» — what and how many, without a code or a currency.
String _itemPhrase(
  BuildContext context,
  Loan loan,
  LoanStanding standing,
  bool persian,
) {
  final strings = lentStrings;
  final what = loan.what.trim().isEmpty
      ? strings(context, 'item')
      : loan.what.trim();
  return strings(context, 'messageItem', {
    'what': what,
    'count': standing.outstanding,
  });
}

/// Lets a person choose a tone, read it, and copy it — one tap. Sharing uses
/// the phone's own sheet, and only when they ask for it.
Future<void> showLoanMessageSheet(
  BuildContext context,
  Loan loan,
  LoanStanding standing,
  IrrUnit unit,
) => nexShowSheet<void>(
  context: context,
  builder: (sheet) =>
      _LoanMessageSheet(loan: loan, standing: standing, unit: unit),
);

class _LoanMessageSheet extends StatefulWidget {
  const _LoanMessageSheet({
    required this.loan,
    required this.standing,
    required this.unit,
  });

  final Loan loan;
  final LoanStanding standing;
  final IrrUnit unit;

  @override
  State<_LoanMessageSheet> createState() => _LoanMessageSheetState();
}

class _LoanMessageSheetState extends State<_LoanMessageSheet> {
  MessageTone _tone = MessageTone.friendly;

  Future<void> _copy() async {
    final messenger = NexBannerHost.of(context);
    final copied = lentStrings(context, 'messageCopied');
    final text = loanMessage(
      context,
      widget.loan,
      widget.standing,
      widget.unit,
      _tone,
    );
    await nexModuleCopyText(text);
    messenger?.show(message: copied);
  }

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final text = loanMessage(
      context,
      widget.loan,
      widget.standing,
      widget.unit,
      _tone,
    );
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(NexSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings(context, 'messageTitle'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: NexSpacing.xs),
              Text(
                strings(context, 'messageHint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              NexAdaptiveSegments<MessageTone>(
                key: const ValueKey('loan-message-tones'),
                segments: [
                  for (final tone in MessageTone.values)
                    ButtonSegment(
                      value: tone,
                      icon: Icon(_toneIcon(tone)),
                      label: Text(strings(context, 'tone_${tone.name}')),
                    ),
                ],
                selected: {_tone},
                onSelectionChanged: (value) =>
                    setState(() => _tone = value.first),
              ),
              const SizedBox(height: NexSpacing.md),
              NexTextSurface(
                text,
                key: ValueKey('loan-message-${_tone.name}'),
                selectable: true,
              ),
              const SizedBox(height: NexSpacing.md),
              FilledButton.icon(
                key: const ValueKey('loan-message-copy'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => unawaited(_copy()),
                icon: const Icon(Icons.copy_outlined),
                label: Text(strings(context, 'messageCopy')),
              ),
              const SizedBox(height: NexSpacing.xs),
              TextButton.icon(
                key: const ValueKey('loan-message-share'),
                onPressed: () => unawaited(nexModuleShareText(text)),
                icon: const Icon(Icons.ios_share),
                label: Text(strings(context, 'messageShare')),
              ),
              const SizedBox(height: NexSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  IconData _toneIcon(MessageTone tone) => switch (tone) {
    MessageTone.friendly => Icons.sentiment_satisfied_outlined,
    MessageTone.neutral => Icons.chat_bubble_outline,
    MessageTone.formal => Icons.badge_outlined,
  };
}
