import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_dates.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'module.dart';
import 'money_format.dart';

/// What a loan's reminder says, decided here so it can be tested without a
/// notification: nothing about the person or the amount unless they chose
/// to show it.
///
/// A locked phone is read by whoever is holding it, so the module's default
/// is the private line. The person turns the detail on for this record, and
/// the choice is kept on the loan so it survives an edit.
String loanReminderBody(
  BuildContext context,
  Loan loan,
  LoanStanding standing,
  IrrUnit unit,
) {
  final strings = lentStrings;
  if (!loan.reminderDetail) {
    return strings(context, 'reminderBodyPrivate');
  }
  final person = loan.person.trim().isEmpty
      ? strings(context, 'untitledPerson')
      : loan.person.trim();
  final amount = loan.kind == LoanKind.money
      ? formatAmount(
          standing.outstanding,
          loan.currency,
          loan.digits,
          NexModuleStrings.persian(context),
          unit,
        )
      : strings(context, 'itemsOut', {'n': standing.outstanding});
  return strings(context, 'reminderBodyDetail', {
    'person': person,
    'amount': amount,
  });
}

/// Re-words an alarm that is already set, after the lock-screen choice
/// changed — otherwise the switch would only affect the *next* reminder, and
/// a person who just turned the detail off would still be shown it at nine.
///
/// The moment is kept exactly: only the words change.
Future<void> rescheduleLoanReminder(
  NexModuleStore store,
  Loan loan,
  LoanStanding standing,
  BuildContext context,
  IrrUnit unit,
) async {
  final body = loanReminderBody(context, loan, standing, unit);
  final title = lentStrings(context, 'reminderTitle');
  for (final record in await store.list('__reminder')) {
    if (record.body['sourceKind'] != 'loan' ||
        record.body['sourceId'] != loan.id) {
      continue;
    }
    final at = DateTime.tryParse('${record.body['at'] ?? ''}')?.toLocal();
    if (at == null || !at.isAfter(DateTime.now())) continue;
    await store.setReminder(
      record.id,
      sourceKind: 'loan',
      sourceId: loan.id,
      at: at,
      title: title,
      body: body,
    );
  }
}

/// The due-date reminder: the platform's own control, with the one choice a
/// reminder like this needs — whether the lock screen says who and how much.
class LoanReminderSection extends StatelessWidget {
  const LoanReminderSection({
    super.key,
    required this.store,
    required this.loan,
    required this.standing,
    required this.unit,
    required this.onDetailChanged,
  });

  final NexModuleStore store;
  final Loan loan;
  final LoanStanding standing;
  final IrrUnit unit;

  /// Saves the choice on the loan; the section itself does not write, so a
  /// failure stays the screen's to report.
  final ValueChanged<bool> onDetailChanged;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexShelfHeading(
          icon: Icons.notifications_none,
          title: strings(context, 'reminderTitle'),
        ),
        const SizedBox(height: NexSpacing.sm),
        NexPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings(context, 'reminderHint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SwitchListTile(
                key: const ValueKey('loan-reminder-detail'),
                contentPadding: EdgeInsets.zero,
                value: loan.reminderDetail,
                onChanged: onDetailChanged,
                title: Text(
                  strings(context, 'reminderShowDetail'),
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  strings(context, 'reminderPrivateNote'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: NexSpacing.xs),
              NexModuleReminderControl(
                store: store,
                sourceKind: 'loan',
                sourceId: loan.id,
                initial: loan.due == null ? null : parseCivilDate(loan.due!),
                body: loanReminderBody(context, loan, standing, unit),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
