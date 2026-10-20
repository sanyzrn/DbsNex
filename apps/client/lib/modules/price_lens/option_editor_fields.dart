part of 'option_editor.dart';

/// The offer editor's scrollable fields, split out of the sheet's build
/// so each file stays small: label, price with currency and rial/toman,
/// quantity with unit, counts, the one discount, shipping, and the
/// shared shopping-date entry. State lives in the sheet; this builds.
extension _OptionEditorFields on _OptionEditorSheetState {
  List<Widget> editorFields(BuildContext context) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    return [
      // A person's own words for the offer: the direction follows the
      // script being typed (ADR-037).
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
      TextField(
        key: const ValueKey('lens-quantity'),
        controller: _quantity,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
      const SizedBox(height: NexSpacing.sm),
      TextField(
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
      if ((parseCount(_count.text) ?? 1) > 1 || _paidCount.text.isNotEmpty) ...[
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
          _paint(() {
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
          _paint(() => _discountKind = kind);
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
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: s(context, 'shippingLabel'),
          hintText: s(context, 'shippingHint'),
          suffixText: _currency.code == 'IRR' && _irrUnit == IrrUnit.toman
              ? s(context, 'tomanUnit')
              : _currency.code,
          errorText:
              _showErrors &&
                  _shipping.text.trim().isNotEmpty &&
                  parseMoneyIn(_shipping.text, _currency, _irrUnit).minor ==
                      null
              ? s(context, 'errNotNumber')
              : null,
        ),
        onChanged: (_) => _markDirty(),
      ),
      const SizedBox(height: NexSpacing.md),
      // The shopping date: typed civil text with the shared Jalali
      // calendar button beside it (storage stays ISO 8601).
      NexModuleDateEntry(
        controller: _dateText,
        child: TextField(
          key: const ValueKey('lens-date'),
          controller: _dateText,
          keyboardType: TextInputType.datetime,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: s(context, 'dateLabel'),
            hintText: s(context, 'dateHint'),
            errorText: _dateProblem ? s(context, 'dateRequired') : null,
          ),
        ),
      ),
      if (_dateText.text.isNotEmpty || !_dateConfirmed)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () {
              _dateText.clear();
              _paint(() => _dateConfirmed = true);
            },
            child: Text(s(context, 'clearDate')),
          ),
        ),
      Text(s(context, 'bundlePriceHint'), style: theme.textTheme.bodySmall),
    ];
  }
}
