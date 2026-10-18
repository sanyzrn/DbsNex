import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'editor_helpers.dart';
import 'money.dart';
import 'options.dart';
import 'option_editor_sections.dart';
import 'price_lens_common.dart';
import 'rational.dart';
import 'strings.dart';
import 'units.dart';
import 'local_values.dart';

part 'option_editor_actions.dart';

/// The offer editor: what it is, the total price with its currency
/// and rial/toman choice, the quantity per package with its unit, the
/// package count (and what was actually paid for, in a buy-N-get-M),
/// one discount applied once, an optional shipping share, and the
/// date. Unsaved work is guarded on the way out.
Future<void> showOptionEditor(
  BuildContext context, {
  required ValueChanged<PriceOption> onSave,
  PriceOption? existing,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  builder: (_) => OptionEditorSheet(existing: existing, onSave: onSave),
);

class OptionEditorSheet extends StatefulWidget {
  const OptionEditorSheet({super.key, required this.onSave, this.existing});

  final PriceOption? existing;
  final ValueChanged<PriceOption> onSave;

  @override
  State<OptionEditorSheet> createState() => _OptionEditorSheetState();
}

class _OptionEditorSheetState extends State<OptionEditorSheet> {
  late final TextEditingController _label = TextEditingController(
    text: widget.existing?.label ?? '',
  );
  late final TextEditingController _price = TextEditingController(
    text: initialPriceText(widget.existing),
  );
  late final TextEditingController _quantity = TextEditingController(
    text: initialQuantityText(widget.existing),
  );
  late final TextEditingController _count = TextEditingController(
    text: '${widget.existing?.packageCount ?? 1}',
  );
  late final TextEditingController _paidCount = TextEditingController(
    text: '${widget.existing?.paidCount ?? ''}',
  );
  late final TextEditingController _discount = TextEditingController(
    text: initialDiscountText(widget.existing, _currency.exponent),
  );
  late final TextEditingController _shipping = TextEditingController(
    text: initialShippingText(widget.existing, _currency.exponent),
  );

  late PriceCurrency _currency = initialCurrencyOf(widget.existing);
  late IrrUnit _irrUnit = IrrUnit.rial;
  late String _unitKey = priceUnitOf(widget.existing?.unitKey)?.key ?? 'kg';
  late DiscountKind _discountKind =
      widget.existing?.discount ?? DiscountKind.none;
  late DateTime? _date = widget.existing?.date;

  late final String _id =
      widget.existing?.id ?? 'opt-${DateTime.now().microsecondsSinceEpoch}';
  bool _dateConfirmed = true;
  bool _unitConfirmed = true, _currencyConfirmed = true;
  bool _saving = false;
  bool _dirty = false;
  bool _showErrors = false;

  PriceUnit get _unit => priceUnitOf(_unitKey)!;

  @override
  void initState() {
    super.initState();
    _unitConfirmed = widget.existing == null || widget.existing!.unit != null;
    _currencyConfirmed =
        widget.existing == null ||
        priceCurrencyOf(widget.existing!.currency) != null;
    _dateConfirmed =
        widget.existing?.source?['date'] == null ||
        widget.existing?.date != null;
  }

  void _paint(VoidCallback action) {
    if (mounted) setState(action);
  }

  @override
  void dispose() {
    _label.dispose();
    _price.dispose();
    _quantity.dispose();
    _count.dispose();
    _paidCount.dispose();
    _discount.dispose();
    _shipping.dispose();
    super.dispose();
  }

  void _markDirty() => setState(() => _dirty = true);

  PriceAmountResult get _parsedPrice =>
      parseMoneyIn(_price.text, _currency, _irrUnit);

  Fraction? get _parsedQuantity => fractionFromDecimal(_quantity.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) unawaited(confirmPriceLensDiscard(context));
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          NexSpacing.md,
          0,
          NexSpacing.md,
          NexSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s(
                      context,
                      widget.existing == null
                          ? 'newOptionTitle'
                          : 'editOptionTitle',
                    ),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: s(context, 'cancel'),
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // A person's own words for the offer: the direction
                    // follows the script being typed (ADR-037).
                    NexAutoDirection(
                      controller: _label,
                      builder: (context, direction) => TextField(
                        key: const ValueKey('lens-label'),
                        controller: _label,
                        autofocus: widget.existing == null,
                        textDirection: direction,
                        decoration: InputDecoration(
                          labelText: s(context, 'labelLabel'),
                          hintText: s(context, 'labelHint'),
                          errorText: _label.text.trim().isEmpty && _showErrors
                              ? s(context, 'labelEmpty')
                              : null,
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                    ),
                    const SizedBox(height: NexSpacing.md),
                    PriceLensMoneyField(
                      key: const ValueKey('lens-price'),
                      controller: _price,
                      label: s(context, 'priceLabel'),
                      currency: _currency,
                      irrUnit: _irrUnit,
                      error: moneyErrorOf(context, _parsedPrice.error),
                      onCurrencyChanged: _currencyChanged,
                      onIrrUnitChanged: _irrChanged,
                      onChanged: _markDirty,
                    ),
                    const SizedBox(height: NexSpacing.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.zero,
                          child: TextField(
                            key: const ValueKey('lens-quantity'),
                            controller: _quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: s(context, 'quantityLabel'),
                              hintText: s(context, 'quantityHint'),
                              errorText: quantityErrorOf(
                                context,
                                showErrors: _showErrors,
                                text: _quantity.text,
                                unitKey: _unitKey,
                              ),
                            ),
                            onChanged: (_) => _markDirty(),
                          ),
                        ),
                        const SizedBox(height: NexSpacing.sm),
                        Padding(
                          padding: EdgeInsets.zero,
                          child: TextField(
                            key: const ValueKey('lens-count'),
                            controller: _count,
                            keyboardType: TextInputType.number,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: s(context, 'bundleCount'),
                              errorText: countErrorOf(
                                context,
                                showErrors: _showErrors,
                                text: _count.text,
                              ),
                            ),
                            onChanged: (_) => _markDirty(),
                          ),
                        ),
                      ],
                    ),
                    if ((parseCount(_count.text) ?? 1) > 1 ||
                        _paidCount.text.isNotEmpty) ...[
                      const SizedBox(height: NexSpacing.sm),
                      TextField(
                        key: const ValueKey('lens-paid-count'),
                        controller: _paidCount,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: s(context, 'paidCount'),
                          helperText: s(context, 'paidCountHint'),
                          errorText:
                              _showErrors &&
                                  ((parseCount(_paidCount.text) ?? 1) >
                                      (parseCount(_count.text) ?? 0))
                              ? s(context, 'paidTooMany')
                              : countErrorOf(
                                  context,
                                  showErrors: _showErrors,
                                  text: _paidCount.text,
                                ),
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                    ],
                    const SizedBox(height: NexSpacing.md),
                    LensUnitPicker(
                      selectedKey: _unitKey,
                      onSelected: (key) {
                        setState(() {
                          _unitKey = key;
                          _unitConfirmed = true;
                        });
                        _markDirty();
                      },
                    ),
                    LensDiscountSection(
                      kind: _discountKind,
                      controller: _discount,
                      currency: _currency,
                      irrUnit: _irrUnit,
                      onKindChanged: (kind) {
                        setState(() => _discountKind = kind);
                        _markDirty();
                      },
                      onChanged: _markDirty,
                      error: discountErrorOf(
                        context,
                        showErrors: _showErrors,
                        kind: _discountKind,
                        text: _discount.text,
                        priceText: _price.text,
                        currency: _currency,
                        irrUnit: _irrUnit,
                      ),
                    ),
                    TextField(
                      key: const ValueKey('lens-shipping'),
                      controller: _shipping,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: s(context, 'shippingLabel'),
                        hintText: s(context, 'shippingHint'),
                        suffixText:
                            _currency.code == 'IRR' && _irrUnit == IrrUnit.toman
                            ? s(context, 'tomanUnit')
                            : _currency.code,
                        errorText:
                            _showErrors &&
                                _shipping.text.trim().isNotEmpty &&
                                parseMoneyIn(
                                      _shipping.text,
                                      _currency,
                                      _irrUnit,
                                    ).minor ==
                                    null
                            ? s(context, 'errNotNumber')
                            : null,
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: NexSpacing.md),
                    InkWell(
                      key: const ValueKey('lens-date'),
                      onTap: () => unawaited(_pickDate()),
                      borderRadius: BorderRadius.circular(NexRadius.md),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: s(context, 'dateLabel'),
                          errorText: _showErrors && !_dateConfirmed
                              ? s(context, 'dateRequired')
                              : null,
                          contentPadding: const EdgeInsetsDirectional.symmetric(
                            horizontal: NexSpacing.md,
                            vertical: NexSpacing.md,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _date == null
                                    ? s(context, 'dateUnset')
                                    : lensFullDate(context, _date!),
                              ),
                            ),
                            const Icon(Icons.calendar_today_outlined, size: 20),
                          ],
                        ),
                      ),
                    ),
                    if (_date != null || !_dateConfirmed)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _date = null;
                            _dateConfirmed = true;
                          });
                          _markDirty();
                        },
                        child: Text(s(context, 'clearDate')),
                      ),
                    Text(
                      s(context, 'bundlePriceHint'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            if (_showErrors)
              Text(
                s(context, 'checkFields'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            FilledButton(
              key: const ValueKey('lens-save'),
              onPressed: _saving ? null : () => unawaited(_save()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(s(context, 'save')),
            ),
          ],
        ),
      ),
    );
  }
}
