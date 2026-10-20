import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_date_entry.dart';
import 'loan_fields.dart';
import 'loan_model.dart';
import 'loan_math.dart';
import 'money_format.dart';
import 'module.dart';

/// The issue date (with its calendar), the due question, and the note —
/// the part of the editor every record shares.
class LoanDateFields extends StatelessWidget {
  const LoanDateFields({
    super.key,
    required this.issueDate,
    required this.dueDate,
    required this.note,
    required this.enabled,
    required this.loan,
    required this.returns,
    this.issueError,
    this.dueError,
  });

  final TextEditingController issueDate, dueDate, note;
  final String? issueError, dueError;
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
        NexModuleDateEntry(
          key: const ValueKey('loan-issue-date-entry'),
          controller: issueDate,
          child: TextField(
            key: const ValueKey('loan-field-issued'),
            controller: issueDate,
            keyboardType: TextInputType.datetime,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: strings(context, 'dateFieldLabel'),
              hintText: strings(context, 'dateHint'),
              errorText: issueError,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionChip(
            key: const ValueKey('loan-issue-today'),
            label: Text(strings(context, 'todayWord')),
            onPressed: enabled
                ? () => issueDate.text = dateEntryText(
                    civilDateKey(DateTime.now()),
                  )
                : null,
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        LoanDueField(
          controller: dueDate,
          errorText: dueError,
          enabled: enabled,
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
