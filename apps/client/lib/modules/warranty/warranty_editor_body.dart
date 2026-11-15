part of 'warranty_editor.dart';

extension _WarrantyEditorBody on _WarrantyEditorSheetState {
  Widget _editorBody(BuildContext context) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);

    // The keyboard must not cover the save button: the module's own body
    // wrapper, because `NexSheetBody` is not part of the module API.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_maybePop());
      },
      child: CheckpointFrame(
        session: _session,
        strings: strings,
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SingleChildScrollView(
            key: const ValueKey('warranty-editor-scroll'),
            padding: const EdgeInsets.all(NexSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings(
                    context,
                    widget.existing != null ? 'editPurchase' : 'addTitle',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.md),
                WarrantyIdentityFields(
                  product: _product,
                  category: _category,
                  brand: _brand,
                  model: _model,
                  serial: _serial,
                  merchant: _merchant,
                  showMore: false,
                  productRequired: _showErrors
                      ? strings(context, 'productRequired')
                      : null,
                ),
                const SizedBox(height: NexSpacing.sm),
                NexModuleDateEntry(
                  controller: _purchaseDate,
                  child: WarrantyFields.line(
                    fieldKey: const ValueKey('warranty-field-purchase'),
                    controller: _purchaseDate,
                    label: strings(context, 'purchaseDate'),
                    hint: strings(context, 'dateHint'),
                    helper: _showErrors && _purchaseBad
                        ? strings(context, 'purchaseRequired')
                        : null,
                  ),
                ),
                // The chip used to sit inside the field, squeezing the
                // label into "Purchase …" at twice the text size. Under the
                // field it keeps the whole width and its own 48dp target.
                const SizedBox(height: NexSpacing.xs),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ActionChip(
                    key: const ValueKey('warranty-today'),
                    label: Text(strings(context, 'today')),
                    onPressed: () {
                      _purchaseDate.text = WarrantyParse.dateText(
                        DateTime.now(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: NexSpacing.lg),
                WarrantyCoverageFields(
                  purchase: _purchaseDate,
                  duration: _duration,
                  endDate: _endDate,
                  coverageType: _coverageType,
                  coverKind: _coverKind,
                  onCoverKind: (kind) {
                    _paint(() {
                      _coverKind = kind;
                      _dirty = true;
                    });
                    _session.changed();
                  },
                  showErrors: _showErrors,
                ),
                // The reminder is offered here, where the person is already
                // saving an end date, rather than buried in the purchase's
                // own page. The platform only lets an installed, available
                // module schedule one, so the offer waits until it can keep
                // the promise instead of failing after every save.
                if (_offerReminder)
                  WarrantyReminderOffer(
                    enabled: _remindOn,
                    onChanged: (value) {
                      _paint(() => _remind = value);
                      _session.changed();
                    },
                    moment: _reminderMoment!,
                    choices: _reminderChoices,
                    selectedDays: _remindDays ?? _reminderChoices.firstOrNull,
                    onDays: (days) {
                      _paint(() => _remindDays = days);
                      _session.changed();
                    },
                    refreshing: widget.existing != null,
                  ),
                const SizedBox(height: NexSpacing.md),
                NexMoreDetails(
                  toggleKey: const ValueKey('warranty-more-toggle'),
                  open: _moreOpen,
                  onChanged: (open) => _paint(() => _more = open),
                  title: strings(context, 'moreDetails'),
                  hint: strings(context, 'moreDetailsHint'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WarrantyIdentityFields(
                        product: _product,
                        category: _category,
                        brand: _brand,
                        model: _model,
                        serial: _serial,
                        merchant: _merchant,
                        showProduct: false,
                      ),
                      const SizedBox(height: NexSpacing.lg),
                      WarrantySupportFields(
                        company: _company,
                        supportPhone: _supportPhone,
                        cardNumber: _cardNumber,
                        registryOwner: _registry,
                        onRegistry: (owner) {
                          _paint(() {
                            _registry = owner;
                            _dirty = true;
                          });
                          _session.changed();
                        },
                      ),
                      const SizedBox(height: NexSpacing.lg),
                      WarrantyFields.line(
                        fieldKey: const ValueKey('warranty-field-receipt'),
                        controller: _receiptRef,
                        label: strings(context, 'receiptRef'),
                        helper: strings(context, 'receiptNote'),
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      WarrantyFields.number(
                        fieldKey: const ValueKey('warranty-field-amount'),
                        decimal: _inTomans,
                        controller: _amount,
                        label: strings(context, 'amount'),
                        hint: strings(context, 'amountHint'),
                        helper: _showErrors && _amountBad
                            ? strings(context, 'amountBad')
                            : null,
                        suffix: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: NexSpacing.xs,
                          ),
                          child: ActionChip(
                            key: const ValueKey('warranty-amount-unit'),
                            label: Text(
                              strings(context, _inTomans ? 'tomans' : 'rials'),
                            ),
                            onPressed: () {
                              final rials = WarrantyParse.rials(
                                _amount.text,
                                inTomans: _inTomans,
                              );
                              if (_amount.text.isNotEmpty && rials == null) {
                                _paint(() => _showErrors = true);
                                return;
                              }
                              _paint(() {
                                _inTomans = !_inTomans;
                                if (rials != null) {
                                  _amount.text = _inTomans
                                      ? WarrantyLogic.tomans(rials)
                                      : '$rials';
                                }
                                _dirty = true;
                              });
                              _session.changed();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      WarrantyTextField(
                        key: const ValueKey('warranty-note'),
                        controller: _note,
                        label: strings(context, 'note'),
                        hint: strings(context, 'noteHint'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NexSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('warranty-save'),
                    onPressed: _session.busy ? null : _save,
                    child: Text(strings(context, 'save')),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('warranty-keep-draft'),
                    onPressed: _session.busy ? null : _keepDraft,
                    child: Text(strings(context, 'keepDraft')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
