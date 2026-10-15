part of 'expenses_editors.dart';

extension _ExpensesTxActions on _ExpensesTxEditorSheetState {
  ExpenseAmountResult get _parsed =>
      _currency.code == 'IRR' && _irrUnit == IrrUnit.toman
      ? parseTomanAmount(_amount.text)
      : parseExpenseAmount(_amount.text, _currency);

  Future<void> _save() async {
    if (!_dateConfirmed) {
      _paint(() => _showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(expenseStrings(context, 'dateRequired'))),
      );
      return;
    }

    final result = _parsed;
    if (result.error != null || result.minor == null) {
      _paint(() => _showErrors = true); // says why Save was refused
      return;
    }
    if (_saving) return;
    _paint(() => _saving = true);
    final tx = ExpenseTx(
      id: _draft.recordId,
      type: _type,
      amount: result.minor!,
      currency: _currency.code,
      date: _date,
      categoryId: _categoryId,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      merchant: _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
      account: _account.text.trim().isEmpty ? null : _account.text.trim(),
    );
    try {
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      await widget.controller.saveTx(
        tx,
        existing: widget.existing,
        draftId: _draft.draftId,
      );
      try {
        await widget.controller.rememberEditorDefaults(
          currencyCode: _currency.code,
          irrUnit: _irrUnit.name,
        );
      } catch (_) {
        /* A saved payment remains saved even if optional defaults fail. */
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _draft.resume();
      _draft.writeFailed = true;
      if (mounted) expenseWriteFailure(context);
    } finally {
      if (mounted) _paint(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final answer = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) => NexAlertDialog(
        title: Text(expenseStrings(context, 'deleteTxTitle')),
        content: NexDialogBody(
          child: Text(expenseStrings(context, 'deleteTxBody')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(expenseStrings(context, 'cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            child: Text(expenseStrings(context, 'delete')),
          ),
        ],
      ),
    );
    if (answer != 'delete' || !mounted) return;
    _paint(() => _saving = true);
    // The messenger and the words are captured while the sheet is still
    // mounted: this context does not outlive the route about to pop.
    final messenger = ScaffoldMessenger.of(context);
    final message = expenseStrings(context, 'deletedTx');
    final undoLabel = expenseStrings(context, 'undo');
    final undoFailure = expenseStrings(context, 'undoFailed');
    try {
      if (!await _draft.finish()) throw StateError("Draft flush failed");
      await widget.controller.deleteTx(existing.id);
      if (mounted) {
        Navigator.pop(context);
        ExpensesUndo.offer(
          messenger,
          message: message,
          undoLabel: undoLabel,
          failureMessage: undoFailure,
          restore: () => widget.controller.restoreTx(existing),
        );
      }
    } catch (_) {
      _draft.resume();
      _draft.writeFailed = true;
      if (mounted) expenseWriteFailure(context);
    } finally {
      if (mounted) _paint(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await nexShowDialog<DateTime>(
      context: context,
      builder: (_) => DatePickerDialog(
        initialDate: !_dateConfirmed
            ? DateTime.now()
            : _date.year > 2100
            ? DateTime(2100, 12, 31)
            : _date,
        firstDate: DateTime(1),
        lastDate: DateTime(2100, 12, 31),
      ),
    );
    if (picked == null || !mounted) return;
    _paint(() {
      _dateConfirmed = true;
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
      );
    });
    _markDirty();
  }

  Future<void> _pickTime() async {
    final picked = await nexShowDialog<TimeOfDay>(
      context: context,
      builder: (_) =>
          TimePickerDialog(initialTime: TimeOfDay.fromDateTime(_date)),
    );
    if (picked == null || !mounted) return;
    _paint(() {
      _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        picked.hour,
        picked.minute,
      );
    });
    _markDirty();
  }

  Future<void> _confirmDiscard() async {
    if (_saving) return;
    await confirmExpensesDiscard(
      context,
      discard: _draft.draft.clear,
      keepDraft: () => _draft.finish(),
    );
  }
}
