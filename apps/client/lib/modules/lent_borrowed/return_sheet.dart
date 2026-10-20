import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_date_entry.dart';
import 'loan_dates.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'money_format.dart';
import 'module.dart';
import 'store_state.dart';
import 'number_input.dart';

/// Records one return: how much came back (never more than is
/// outstanding), and when — an absolute date with the shared calendar
/// beside it, defaulting to today.
Future<void> showReturnSheet(
  BuildContext context,
  NexModuleStore store, {
  required Loan loan,
  required List<LoanReturn> returns,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (context) =>
      _ReturnSheet(store: store, loan: loan, returns: returns),
);

class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({
    required this.store,
    required this.loan,
    required this.returns,
  });

  final NexModuleStore store;
  final Loan loan;
  final List<LoanReturn> returns;

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _date;
  bool _saving = false;
  late final String _recordId = widget.store.newId();
  String? _amountError;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    // The sheet offers the whole outstanding amount as its starting point:
    // the common case is everything coming back at once.
    _amount = TextEditingController(
      text: widget.loan.kind == LoanKind.money
          ? moneyInput(
              LoanMath.standing(widget.loan, widget.returns).outstanding,
              widget.loan.digits,
            )
          : '${LoanMath.standing(widget.loan, widget.returns).outstanding}',
    );
    _date = TextEditingController(
      text: dateEntryText(civilDateKey(DateTime.now())),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = lentStrings;
    final amount = widget.loan.kind == LoanKind.money
        ? parseMoney(_amount.text, widget.loan.digits)
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
      final history = (await widget.store.list(
        'return',
      )).map(LoanReturn.fromRecord).toList();
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
    if (saved) Navigator.of(context).pop();
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
                strings(context, 'recordReturn'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: NexSpacing.sm),
              Text(
                strings(context, 'outstanding', {
                  'amount': isMoney
                      ? formatMoney(
                          standing.outstanding,
                          widget.loan.currency,
                          widget.loan.digits,
                          persian,
                        )
                      : formatNumber(standing.outstanding, persian),
                }),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              TextField(
                key: const ValueKey('return-field-amount'),
                controller: _amount,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: isMoney && widget.loan.digits > 0,
                ),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: strings(
                    context,
                    isMoney ? 'returnAmount' : 'returnQuantity',
                  ),
                  errorText: _amountError,
                  suffixText: isMoney ? widget.loan.currency : null,
                  border: const OutlineInputBorder(),
                ),
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
                    border: const OutlineInputBorder(),
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
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              const SizedBox(height: NexSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
