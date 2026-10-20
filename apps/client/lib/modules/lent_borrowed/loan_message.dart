import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_dates.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'money_format.dart';
import 'module.dart';

enum MessageTone { friendly, plain, formal }

/// A polite note a person can send themselves: what is still out, and when it
/// was due. Built here, handed to the system share sheet only when they ask;
/// nothing is sent by the app.
String loanMessage(
  BuildContext context,
  Loan loan,
  LoanStanding standing,
  MessageTone tone,
) {
  final strings = lentStrings;
  final persian = NexModuleStrings.persian(context);
  final person = loan.person.trim().isEmpty
      ? strings(context, 'untitledPerson')
      : loan.person.trim();
  final amount = loan.kind == LoanKind.money
      ? formatMoney(standing.outstanding, loan.currency, loan.digits, persian)
      : '${loan.what.isEmpty ? strings(context, 'item') : loan.what}'
            ' × ${formatNumber(standing.outstanding, persian)}';
  final due = loan.due == null ? null : parseCivilDate(loan.due!);
  final clause = due == null
      ? ''
      : strings(context, 'messageDue', {
          'date': nexModuleDateLabel(context, due),
        });
  return strings(context, 'message_${tone.name}', {
    'person': person,
    'amount': amount,
    'due': clause,
  });
}

/// Lets a person choose a tone and shares the message; nothing leaves the
/// phone until they pick where it goes.
Future<void> showLoanMessageSheet(
  BuildContext context,
  Loan loan,
  LoanStanding standing,
) => nexShowSheet<void>(
  context: context,
  builder: (sheet) {
    final strings = lentStrings;
    final theme = Theme.of(sheet);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(NexSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings(sheet, 'messageTitle'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              strings(sheet, 'messageHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            for (final tone in MessageTone.values)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  bottom: NexSpacing.sm,
                ),
                child: Material(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(NexRadius.lg),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('loan-message-${tone.name}'),
                    onTap: () {
                      final text = loanMessage(sheet, loan, standing, tone);
                      Navigator.of(sheet).pop();
                      unawaited(nexModuleShareText(text));
                    },
                    child: Padding(
                      padding: const EdgeInsetsDirectional.all(NexSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings(sheet, 'tone_${tone.name}'),
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: NexSpacing.xs),
                          Text(
                            loanMessage(sheet, loan, standing, tone),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  },
);
