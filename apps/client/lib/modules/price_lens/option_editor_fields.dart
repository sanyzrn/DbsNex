part of 'option_editor.dart';

extension _OptionEditorFields on _OptionEditorSheetState {
  List<Widget> editorFields(BuildContext context) {
    final s = priceLensStrings;
    return [
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
        ),
      ),
      const SizedBox(height: NexSpacing.md),
      PriceLensMoneyField(
        key: const ValueKey('lens-price'),
        legacyMinor: widget.priceEntry ? null : widget.existing?.priceMinor,
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
      ),
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
      const SizedBox(height: NexSpacing.md),
      if (_details)
        ..._extraFields(context)
      else
        NexMoreDetails(
          open: _details,
          onChanged: (open) {
            _paint(() => _details = open);
            _markDirty();
          },
          title: s(context, 'moreDetails'),
          hint: s(context, 'detailsHint'),
          toggleKey: const ValueKey('lens-details'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _extraFields(context),
          ),
        ),
    ];
  }

  List<Widget> _extraFields(BuildContext context) {
    final s = priceLensStrings;
    return [
      NexTextField(
        key: const ValueKey('lens-product'),
        controller: _product,
        minLines: 1,
        maxLines: 2,
        maxLength: 150,
        decoration: InputDecoration(
          labelText: s(context, 'productName'),
          hintText: s(context, 'productNameHint'),
        ),
      ),
      const SizedBox(height: NexSpacing.md),
      NexTextField(
        key: const ValueKey('lens-shop'),
        controller: _shop,
        minLines: 1,
        maxLines: 2,
        maxLength: 100,
        decoration: InputDecoration(labelText: s(context, 'shopLabel')),
      ),
      const SizedBox(height: NexSpacing.md),
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
        ),
      ],
      const SizedBox(height: NexSpacing.md),
      LensDiscountSection(
        kind: _discountKind,
        controller: _discount,
        currency: _currency,
        irrUnit: _irrUnit,
        legacyMinor: widget.existing?.discountMinor,
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
      const SizedBox(height: NexSpacing.md),
      if (lensAmountsHidden(context))
        const Text('••••')
      else
        LensAmountEntry(
          legacyMinor: widget.existing?.shippingMinor,
          fieldKey: const ValueKey('lens-shipping'),
          controller: _shipping,
          currency: _currency.code,
          digits: _currency.code == 'IRR' ? 0 : _currency.exponent,
          unit: _irrUnit,
          label: s(context, 'shippingLabel'),
          hint: s(context, 'shippingHint'),
          errorText: _showErrors && _shipping.text.trim().isNotEmpty
              ? moneyErrorOf(
                  context,
                  parseMoneyIn(_shipping.text, _currency, _irrUnit).error,
                )
              : null,
        ),
      const SizedBox(height: NexSpacing.md),
      if (NexModuleStrings.persian(context))
        NexModuleCalendar(
          solar: true,
          child: Builder(
            builder: (calendarContext) => TextButton.icon(
              key: const ValueKey('lens-date'),
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await nexPickModuleDate(
                  calendarContext,
                  initial: _parsedDate ?? now,
                  first: DateTime(1900),
                  last: now,
                );
                if (picked != null && mounted) {
                  _dateText.text =
                      '${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}';
                  _paint(() => _dateConfirmed = true);
                }
              },
              label: Text(
                _parsedDate == null
                    ? s(context, 'chooseDate')
                    : nexReadableDate(_parsedDate!, solar: true, persian: true),
              ),
            ),
          ),
        )
      else
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
      if (NexModuleStrings.persian(context) && _dateProblem)
        Text(s(context, 'dateRequired')),
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
      Text(
        s(context, 'bundlePriceHint'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }
}
