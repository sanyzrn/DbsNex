part of 'option_editor.dart';

extension _OfferActions on _OptionEditorSheetState {
  Future<void> _pickDate() async {
    final now = DateTime.now(), candidate = _date ?? DateTime.now();
    final picked = await nexShowDialog<DateTime>(
      context: context,
      builder: (_) => DatePickerDialog(
        initialDate: candidate.isAfter(now) ? now : candidate,
        firstDate: DateTime(1),
        lastDate: now,
      ),
    );
    if (picked == null || !mounted) return;
    _paint(() {
      _date = picked;
      _dateConfirmed = true;
    });
    _markDirty();
  }

  Future<void> _save() async {
    final price = _parsedPrice;
    final quantity = _parsedQuantity;
    final count = parseCount(_count.text);
    final paidText = _paidCount.text.trim();
    final paid = paidText.isEmpty ? null : parseCount(paidText);

    int? percent;
    int? fixedMinor;
    if (_discountKind == DiscountKind.percent) {
      percent = LocalValues.writtenCount(_discount.text.trim());
    } else if (_discountKind == DiscountKind.fixed) {
      fixedMinor = parseMoneyIn(_discount.text, _currency, _irrUnit).minor;
    }
    int? shippingMinor;
    var shippingBad = false;
    if (_shipping.text.trim().isNotEmpty) {
      final parsed = parseMoneyIn(_shipping.text, _currency, _irrUnit);
      shippingMinor = parsed.minor;
      shippingBad = parsed.minor == null;
    }

    final problems = <bool>[
      !_unitConfirmed || !_currencyConfirmed,
      _label.text.trim().isEmpty,
      price.error != null,
      quantity == null || quantity <= const Fraction(0),
      quantityDecimalsOf(_quantity.text) > _unit.decimals,
      count == null || count == -1,
      paid != null && (paid == -1 || count == null || paid > count),
      !_dateConfirmed || (_date != null && _date!.isAfter(DateTime.now())),
      _discountKind == DiscountKind.fixed &&
          fixedMinor != null &&
          price.minor != null &&
          fixedMinor > price.minor!,
      _discountKind == DiscountKind.percent &&
          (percent == null || percent < 0 || percent > 100),
      _discountKind == DiscountKind.fixed && fixedMinor == null,
      shippingBad,
    ];
    if (problems.contains(true)) {
      _paint(() => _showErrors = true);
      return;
    }
    if (_saving) return;
    _paint(() => _saving = true);
    final option = PriceOption(
      id: _id,
      label: _label.text.trim(),
      priceMinor: price.minor!,
      currency: _currency.code,
      quantity: quantity!,
      unitKey: _unitKey,
      packageCount: count!,
      paidCount: paid,
      discount: _discountKind,
      discountPercent: percent,
      discountMinor: fixedMinor,
      shippingMinor: shippingMinor,
      date: _date,
    );
    if (!optionSafe(option)) {
      _paint(() {
        _saving = false;
        _showErrors = true;
      });
      return;
    }
    widget.onSave(option);
    if (mounted) {
      _paint(() => _saving = false);
      Navigator.pop(context);
    }
  }

  void _currencyChanged(PriceCurrency currency) {
    _paint(() {
      _currencyConfirmed = true;
      _currency = currency;
      _irrUnit = IrrUnit.rial;
    });
    _markDirty();
  }

  void _irrChanged(IrrUnit unit) {
    if (unit == _irrUnit) return;
    for (final c in [
      _price,
      if (_discountKind == DiscountKind.fixed) _discount,
      _shipping,
    ]) {
      final parsed = parseMoneyIn(c.text, _currency, _irrUnit);
      if (parsed.minor != null) {
        c.text = priceMajorText(parsed.minor!, unit == IrrUnit.toman ? 3 : 2);
      }
    }
    _paint(() => _irrUnit = unit);
    _markDirty();
  }
}
