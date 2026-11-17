import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_date_entry.dart';
import 'loan_fields.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'module.dart';
import 'money_format.dart';

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
    required this.unit,
    this.issueError,
    this.dueError,
  });

  final TextEditingController issueDate, dueDate, note;
  final String? issueError, dueError;
  final bool enabled;
  final Loan? loan;
  final List<LoanReturn> returns;
  final IrrUnit unit;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final editing = loan;
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
          decoration: InputDecoration(labelText: strings(context, 'noteLabel')),
        ),
        if (editing != null) ...[
          const SizedBox(height: NexSpacing.sm),
          Text(
            _ofTotal(context, editing, persian),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// «۲۰۰٬۰۰۰ تومان از ۵۰۰٬۰۰۰ تومان برگشته» — what an edit may not take
  /// away, said before the person changes the total.
  String _ofTotal(BuildContext context, Loan loan, bool persian) {
    final strings = lentStrings;
    final standing = LoanMath.standing(loan, returns);
    String amount(int minor) => loan.kind == LoanKind.money
        ? formatAmount(minor, loan.currency, loan.digits, persian, unit)
        : formatNumber(minor, persian);
    return strings(context, 'ofTotal', {
      'done': amount(standing.returned),
      'total': amount(loan.amount),
    });
  }
}
