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
            padding: const EdgeInsets.all(NexSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings(
                    context,
                    widget.existing != null ? 'editPurchase' : 'add',
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
                  productRequired: _showErrors
                      ? strings(context, 'productRequired')
                      : null,
                ),
                WarrantyFields.line(
                  fieldKey: const ValueKey('warranty-field-purchase'),
                  controller: _purchaseDate,
                  label: strings(context, 'purchaseDate'),
                  hint: strings(context, 'dateHint'),
                  helper: _showErrors && _purchaseBad
                      ? strings(context, 'purchaseRequired')
                      : null,
                  suffix: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: NexSpacing.xs,
                    ),
                    child: ActionChip(
                      key: const ValueKey('warranty-today'),
                      label: Text(strings(context, 'today')),
                      onPressed: () {
                        final now = DateTime.now();
                        _purchaseDate.text =
                            '${now.year}/${now.month}/${now.day}';
                      },
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.lg),
                WarrantyCoverageFields(
                  purchase: _purchaseDate,
                  duration: _duration,
                  endDate: _endDate,
                  coverageType: _coverageType,
                  showErrors: _showErrors,
                ),
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
                  hint: strings(context, 'noteHint'),
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
