import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'amount_field.dart';
import 'form_draft.dart';
import 'irr_unit.dart';
import 'loan_date_entry.dart';
import 'loan_dates.dart';
import 'loan_fields.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'module.dart';
import 'money_format.dart';
import 'number_input.dart';
import 'store_state.dart';

/// Records one return: how much came back (never more than is
/// outstanding), and when — an absolute date with the shared calendar
/// beside it, defaulting to today.
Future<void> showReturnSheet(
  BuildContext context,
  NexModuleStore store, {
  required Loan loan,
  required List<LoanReturn> returns,
  required IrrUnit unit,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (context) =>
      _ReturnSheet(store: store, loan: loan, returns: returns, unit: unit),
);

class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({
    required this.store,
    required this.loan,
    required this.returns,
    required this.unit,
  });

  final NexModuleStore store;
  final Loan loan;
  final List<LoanReturn> returns;
  final IrrUnit unit;

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _date;
  late final FormDraft _draft;
  bool _saving = false;
  bool _restoring = true;
  late final String _recordId = widget.store.newId();
  String? _amountError;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    // The sheet offers the whole outstanding amount as its starting point:
    // the common case is everything coming back at once.
    final outstanding = LoanMath.standing(
      widget.loan,
      widget.returns,
    ).outstanding;
    _amount = TextEditingController(
      text: widget.loan.kind == LoanKind.money
          ? amountInput(
              outstanding,
              widget.loan.currency,
              widget.loan.digits,
              widget.unit,
            )
          : '$outstanding',
    );
    _date = TextEditingController(
      text: dateEntryText(civilDateKey(DateTime.now())),
    );
    // A sheet that is swiped away keeps what was typed, as every Nex form
    // does; only an explicit Cancel throws it away.
    _draft = FormDraft(widget.store, 'return:${widget.loan.id}', const {}, {
      'amount': _amount,
      'date': _date,
    }, () => const {});
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final body = await _draft.load();
    if (!mounted) return;
    if (body != null) _draft.apply(body);
    _draft.start();
    setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _draft.close();
    _amount.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = lentStrings;
    final amount = widget.loan.kind == LoanKind.money
        ? parseAmount(
            _amount.text,
            widget.loan.currency,
            widget.loan.digits,
            widget.unit,
          )
        : parseWhole(_amount.text, max: maxMoney);
    final date = parseDateEntry(_date.text.trim());

    final fromToday = date == null
        ? null
        : civilDaysBetween(date, civilDateKey(DateTime.now()));
    final fromIssue = date == null
        ? null
        : civilDaysBetween(widget.loan.issued, date);

    setState(() {
      _dateError = date == null
          ? strings(context, 'dateInvalid')
          : (fromToday ?? 0) < 0
          ? strings(context, 'returnFutureDate')
          : (fromIssue ?? 0) < 0
          ? strings(context, 'returnBeforeIssue')
          : null;
      if (amount == null) {
        _amountError = strings(context, 'numberInvalid');
      } else {
        // The one rule that cannot bend: never more than what is out.
        final error = LoanMath.returnError(widget.loan, widget.returns, amount);
        _amountError = switch (error) {
          'zero' => strings(context, 'zeroAmount'),
          'over' => strings(context, 'overpay'),
          _ => null,
        };
      }
    });
    if (_amountError != null || _dateError != null) return;

    if (_saving) return;
    setState(() => _saving = true);
    final written = date!;
    final saved = await storeWrite(context, () async {
      final body = await widget.store.get('loan', widget.loan.id);
      if (body == null) throw StateError('Missing loan');
      final fresh = Loan.fromBody(widget.loan.id, body);
      final history = (await widget.store.list('return'))
          .map(LoanReturn.fromRecord)
          .toList();
      if (fresh.kind != widget.loan.kind ||
          fresh.currency != widget.loan.currency ||
          fresh.digits != widget.loan.digits ||
          LoanMath.returnError(fresh, history, amount!) != null) {
        throw StateError('Balance changed');
      }
      final today = civilDateKey(DateTime.now());
      if ((civilDaysBetween(written, today) ?? 0) < 0) {
        throw StateError('Return dated in the future');
      }
      if ((civilDaysBetween(fresh.issued, written) ?? 0) < 0) {
        throw StateError('Return precedes issue');
      }
      await widget.store.put('return', _recordId, {
        'loan': widget.loan.id,
        'date': written,
        'amount': amount,
      });
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) return;
    try {
      await _draft.clear();
    } catch (_) {
      /* The saved return is authoritative. */
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    try {
      await _draft.clear();
    } catch (_) {
      /* A leftover draft is read as the person's own typing next time. */
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final persian = NexModuleStrings.persian(context);
    final standing = LoanMath.standing(widget.loan, widget.returns);
    final isMoney = widget.loan.kind == LoanKind.money;

    return PopScope(
      canPop: !_saving,
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
                const SizedBox(height: NexSpacing.md),
                Text(
                  strings(context, 'recordReturn'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.sm),
                Text(
                  strings(context, 'outstanding', {
                    'amount': isMoney
                        ? formatAmount(
                            standing.outstanding,
                            widget.loan.currency,
                            widget.loan.digits,
                            persian,
                            widget.unit,
                          )
                        : formatNumber(standing.outstanding, persian),
                  }),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                if (isMoney)
                  AmountField(
                    controller: _amount,
                    currency: widget.loan.currency,
                    digits: widget.loan.digits,
                    unit: widget.unit,
                    label: strings(context, 'returnAmount'),
                    errorText: _amountError,
                    enabled: !_saving,
                    fieldKey: const ValueKey('return-field-amount'),
                    wordsKey: const ValueKey('return-amount-words'),
                  )
                else
                  LoanNumberField(
                    fieldKey: const ValueKey('return-field-amount'),
                    controller: _amount,
                    label: strings(context, 'returnQuantity'),
                    errorText: _amountError,
                  ),
                const SizedBox(height: NexSpacing.md),
                Text(
                  strings(context, 'returnDate'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: NexSpacing.sm),
                NexModuleDateEntry(
                  key: const ValueKey('return-date-entry'),
                  controller: _date,
                  child: TextField(
                    key: const ValueKey('return-field-date'),
                    controller: _date,
                    keyboardType: TextInputType.datetime,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: strings(context, 'dateFieldLabel'),
                      hintText: strings(context, 'dateHint'),
                      errorText: _dateError,
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ActionChip(
                    key: const ValueKey('return-date-today'),
                    label: Text(strings(context, 'todayWord')),
                    onPressed: _saving
                        ? null
                        : () => _date.text = dateEntryText(
                            civilDateKey(DateTime.now()),
                          ),
                  ),
                ),
                const SizedBox(height: NexSpacing.lg),
                FilledButton(
                  key: const ValueKey('return-save'),
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
                  onPressed: _saving ? null : _cancel,
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
