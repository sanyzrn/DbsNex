import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'loan_fields.dart';
import 'loan_model.dart';
import 'loan_math.dart';
import 'money_format.dart';
import 'module.dart';

class LoanDateFields extends StatelessWidget {
  const LoanDateFields({
    super.key,
    required this.daysAgo,
    required this.dueIn,
    required this.note,
    required this.enabled,
    required this.loan,
    required this.returns,
    this.daysError,
    this.dueError,
  });
  final TextEditingController daysAgo, dueIn, note;
  final String? daysError, dueError;
  final bool enabled;
  final Loan? loan;
  final List<LoanReturn> returns;
  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings(context, 'issueLabel'), style: theme.textTheme.titleSmall),
        const SizedBox(height: NexSpacing.sm),
        LoanNumberField(
          key: const ValueKey('loan-field-issued'),
          controller: daysAgo,
          label: strings(context, 'issuedDaysAgo'),
          hint: strings(context, 'daysAgoHint'),
          errorText: daysError,
        ),
        const SizedBox(height: NexSpacing.md),
        LoanDueField(
          controller: dueIn,
          errorText: dueError,
          enabled: !!enabled,
        ),
        const SizedBox(height: NexSpacing.md),
        NexTextField(
          key: const ValueKey('loan-field-note'),
          controller: note,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: strings(context, 'noteLabel'),
            border: const OutlineInputBorder(),
          ),
        ),
        if (loan != null) ...[
          const SizedBox(height: NexSpacing.sm),
          Text(
            '${strings(context, 'ofTotal', {'done': loan!.kind == LoanKind.money ? formatMoney(LoanMath.standing(loan!, returns).returned, loan!.currency, loan!.digits, persian) : formatNumber(LoanMath.standing(loan!, returns).returned, persian), 'total': loan!.kind == LoanKind.money ? formatMoney(loan!.amount, loan!.currency, loan!.digits, persian) : formatNumber(loan!.amount, persian)})} — ${strings(context, 'editRecord')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
