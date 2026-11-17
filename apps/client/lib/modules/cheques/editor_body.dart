part of 'editor.dart';

extension _ChequeEditorBody on _ChequeEditorState {
  Widget _body(BuildContext context) {
    final s = chequeStrings,
        amount = enteredAmount(_fields['amount']!.text, _unit);
    return DraftGuard(
      draft: _draft,
      busy: () => _loading || _saving,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(s(context, widget.cheque == null ? 'add' : 'edit')),
          actions: const [ChequePrivacyButton()],
        ),
        body: _failed
            ? NexEmptyState(
                icon: Icons.refresh,
                message: s(context, 'readError'),
                action: TextButton(
                  onPressed: _load,
                  child: Text(s(context, 'retry')),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  NexSpacing.md,
                  NexSpacing.md,
                  NexSpacing.xl + nexBottomInset(context),
                ),
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  AbsorbPointer(
                    absorbing: _loading || _saving || _committed != null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChequeChoices(
                          values: const ['incoming', 'outgoing'],
                          value: _direction,
                          onChanged: locked
                              ? null
                              : (v) {
                                  _update(() => _direction = v);
                                  _draft.changed();
                                },
                        ),
                        const SizedBox(height: NexSpacing.sm),
                        ChequeChoices(
                          values: const ['payment', 'guarantee'],
                          value: _purpose,
                          onChanged: locked
                              ? null
                              : (v) {
                                  _update(() => _purpose = v);
                                  _draft.changed();
                                },
                        ),
                        if (locked)
                          Text(
                            s(context, 'locked'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: NexSpacing.md),
                        NexTextField(
                          key: const ValueKey('cheque-party'),
                          controller: _fields['party']!,
                          minLines: 1,
                          maxLines: 2,
                          maxLength: 100,
                          decoration: InputDecoration(
                            labelText: s(context, 'party'),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: NexSpacing.md),
                        ChequeChoices(
                          values: const ['toman', 'rial'],
                          value: _unit,
                          onChanged: _unitChange,
                        ),
                        const SizedBox(height: NexSpacing.sm),
                        ChequePrivateInput(
                          hidden: chequeHidden(context),
                          child: AmountField(
                            fieldKey: const ValueKey('cheque-amount'),
                            controller: _fields['amount']!,
                            currency: 'IRR',
                            digits: 0,
                            unit: IrrUnit.fromKey(_unit),
                            enabled: !locked,
                            label: s(context, 'amount'),
                          ),
                        ),
                        if (amount != null)
                          Text(
                            s(context, 'conversion', {
                              'amount': chequeMoney(
                                context,
                                amount,
                                unit: _unit == 'rial' ? 'toman' : 'rial',
                              ),
                              'unit': s(
                                context,
                                _unit == 'rial' ? 'toman' : 'rial',
                              ),
                            }),
                          ),
                        const SizedBox(height: NexSpacing.md),
                        Text(
                          s(
                            context,
                            _purpose == 'guarantee' ? 'followUp' : 'due',
                          ),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        TextButton.icon(
                          key: const ValueKey('cheque-date'),
                          onPressed: _pickDay,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            _day == null
                                ? s(context, 'chooseDate')
                                : nexModuleDateLabel(context, _day!),
                          ),
                        ),
                        if (_purpose == 'guarantee' && _day != null)
                          TextButton(
                            onPressed: () {
                              _update(() => _day = null);
                              _draft.changed();
                            },
                            child: Text(s(context, 'clearRange')),
                          ),
                        const SizedBox(height: NexSpacing.md),
                        ChequeEditorOptions(
                          fields: _fields,
                          open: _details,
                          remind: _remind,
                          days: _days,
                          minutes: _minutes,
                          sayadState: _sayadState,
                          change: _change,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: NexSpacing.md,
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: NexSpacing.md),
                  FilledButton.icon(
                    key: const ValueKey('cheque-save'),
                    onPressed: _loading || _saving ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(
                      s(context, _committed == null ? 'save' : 'retry'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
