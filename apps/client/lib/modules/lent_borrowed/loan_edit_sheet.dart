import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_math.dart';
import 'loan_fields.dart';
import 'loan_model.dart';
import 'money_format.dart';
import 'module.dart';
import 'adaptive_segments.dart';
import 'store_state.dart';
import 'form_draft.dart';
import 'draft_guard.dart';
import 'currency_field.dart';
import 'loan_date_fields.dart';
import 'number_input.dart';
import 'loan_dates.dart';

part 'loan_edit_logic.dart';

/// Creates a lent or borrowed record — or edits one without ever touching
/// its return history. Dates are asked the honest way: "N days ago" for
/// the issue date, "in N days" for the due date, with quick presets,
/// because the module API has no calendar picker to draw.
Future<void> showLoanEditSheet(
  BuildContext context,
  NexModuleStore store, {
  Loan? editing,
  List<LoanReturn> returns = const [],
  LoanDirection initialDirection = LoanDirection.lent,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (context) => _LoanEditSheet(
    store: store,
    editing: editing,
    returns: returns,
    initialDirection: initialDirection,
  ),
);

class _LoanEditSheet extends StatefulWidget {
  const _LoanEditSheet({
    required this.store,
    required this.editing,
    required this.returns,
    required this.initialDirection,
  });

  final NexModuleStore store;
  final Loan? editing;
  final List<LoanReturn> returns;
  final LoanDirection initialDirection;

  @override
  State<_LoanEditSheet> createState() => _LoanEditSheetState();
}

class _LoanEditSheetState extends State<_LoanEditSheet> with _LoanEditLogic {
  @override
  Widget build(BuildContext context) {
    if (!_restoring) _draft.changed();
    final strings = lentStrings;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DraftGuard(
      draft: _draft,
      busy: () => _saving,
      child: AbsorbPointer(
        absorbing: _restoring || _saving,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: NexSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: NexSpacing.md),
                Text(
                  strings(
                    context,
                    widget.editing == null ? 'newRecord' : 'editRecord',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.md),
                AdaptiveSegments<LoanDirection>(
                  key: const ValueKey('loan-field-direction'),
                  segments: [
                    ButtonSegment(
                      value: LoanDirection.lent,
                      icon: const Icon(Icons.north_east_outlined),
                      label: Text(strings(context, 'iLent')),
                    ),
                    ButtonSegment(
                      value: LoanDirection.borrowed,
                      icon: const Icon(Icons.south_west_outlined),
                      label: Text(strings(context, 'iBorrowed')),
                    ),
                  ],
                  selected: {_direction},
                  onSelectionChanged: _saving
                      ? null
                      : (value) => setState(() => _direction = value.first),
                ),
                const SizedBox(height: NexSpacing.md),
                AdaptiveSegments<LoanKind>(
                  key: const ValueKey('loan-field-kind'),
                  segments: [
                    ButtonSegment(
                      value: LoanKind.money,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(strings(context, 'money')),
                    ),
                    ButtonSegment(
                      value: LoanKind.item,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(strings(context, 'item')),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _saving || _myReturns.isNotEmpty
                      ? null
                      : (value) => setState(() => _kind = value.first),
                ),
                const SizedBox(height: NexSpacing.md),
                NexAutoDirection(
                  controller: _person,
                  builder: (context, _) => TextField(
                    key: const ValueKey('loan-field-person'),
                    controller: _person,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: strings(context, 'personLabel'),
                      hintText: strings(context, 'personHint'),
                      errorText: _personError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                if (_kind == LoanKind.money) ...[
                  CurrencyField(
                    key: const ValueKey('loan-field-currency'),
                    value: _currency,
                    onChanged: _saving || _myReturns.isNotEmpty
                        ? null
                        : (code) => setState(() {
                            _currency = code;
                            _digits = moneyDigits(code);
                            _amount.clear();
                          }),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  LoanNumberField(
                    key: const ValueKey('loan-field-amount'),
                    controller: _amount,
                    label: strings(context, 'amountLabel'),
                    errorText: _amountError,
                    hint: strings(context, 'amountHint', {
                      'example': localDigits(
                        moneyInput(12345, _digits),
                        NexModuleStrings.persian(context),
                      ),
                    }),
                    suffix: _currency,
                    decimal: _digits > 0,
                  ),
                ] else ...[
                  NexAutoDirection(
                    controller: _what,
                    builder: (context, _) => TextField(
                      key: const ValueKey('loan-field-what'),
                      controller: _what,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: strings(context, 'whatLabel'),
                        hintText: strings(context, 'whatHint'),
                        errorText: _whatError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  LoanNumberField(
                    key: const ValueKey('loan-field-quantity'),
                    controller: _quantity,
                    label: strings(context, 'quantityLabel'),
                    errorText: _quantityError,
                  ),
                ],
                const SizedBox(height: NexSpacing.md),
                LoanDateFields(
                  daysAgo: _daysAgo,
                  dueIn: _dueIn,
                  note: _note,
                  enabled: !_saving,
                  loan: widget.editing,
                  returns: _myReturns,
                  daysError: _daysError,
                  dueError: _dueError,
                ),
                const SizedBox(height: NexSpacing.lg),
                FilledButton(
                  key: const ValueKey('loan-save'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _saving ? null : () => _save(),
                  child: _saving
                      ? const NexInlineSpinner(size: 20)
                      : Text(l10n.save),
                ),
                const SizedBox(height: NexSpacing.sm),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          await _draft.clear();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  child: Text(l10n.cancel),
                ),
                const SizedBox(height: NexSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
