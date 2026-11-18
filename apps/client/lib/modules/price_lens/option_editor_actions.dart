part of 'option_editor.dart';

extension _OfferActions on _OptionEditorSheetState {
  Future<void> _save() async {
    if (_committed != null) {
      await _finishSave();
      return;
    }
    final price = _parsedPrice;
    final quantity = _parsedQuantity;
    final count = parseCount(_count.text);
    final paidText = _paidCount.text.trim();
    final paid = paidText.isEmpty ? null : parseCount(paidText);
    final dateText = _dateText.text.trim();
    final date = dateText.isEmpty ? null : LocalValues.day(dateText);

    int? percent;
    int? fixedMinor;
    if (_discountKind == DiscountKind.percent) {
      percent = LocalValues.writtenCount(_discount.text.trim());
    } else if (_discountKind == DiscountKind.fixed) {
      fixedMinor = parseMoneyIn(
        _discount.text,
        _currency,
        _irrUnit,
        legacyMinor: widget.existing?.discountMinor,
      ).minor;
    }
    int? shippingMinor;
    var shippingBad = false;
    if (_shipping.text.trim().isNotEmpty) {
      final parsed = parseMoneyIn(
        _shipping.text,
        _currency,
        _irrUnit,
        legacyMinor: widget.existing?.shippingMinor,
      );
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
      !_dateConfirmed || (dateText.isNotEmpty && date == null),
      date != null && date.isAfter(DateTime.now()),
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
      _paint(() {
        _showErrors = true;
        _details = true;
      });
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
      date: date,
      productName: _product.text.trim().isEmpty ? null : _product.text.trim(),
      person: {...?widget.existing?.person, 'name': _shop.text.trim()},
      source: widget.existing?.source,
    );
    if (!optionSafe(option)) {
      _paint(() {
        _saving = false;
        _showErrors = true;
      });
      return;
    }
    try {
      if (widget.persist != null) await widget.persist!(option);
      _committed = option;
      widget.onSave(option);
      await _finishSave();
    } catch (_) {
      if (mounted) {
        _paint(() => _saving = false);
        nexShowBanner(
          context,
          message: priceLensStrings(context, 'saveFailed'),
          kind: NexBannerKind.failed,
        );
      }
    }
  }

  Future<void> _finishSave() async {
    if (_draft != null && !await _draft.clear()) {
      if (mounted) {
        _paint(() => _saving = false);
        nexShowBanner(
          context,
          message: priceLensStrings(context, 'draftCleanup'),
          kind: NexBannerKind.failed,
        );
      }
      return;
    }
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
    final values = <TextEditingController, String>{};
    for (final c in [
      _price,
      if (_discountKind == DiscountKind.fixed) _discount,
      _shipping,
    ]) {
      final legacy = c == _price
          ? widget.existing?.priceMinor
          : c == _shipping
          ? widget.existing?.shippingMinor
          : widget.existing?.discountMinor;
      final parsed = parseMoneyIn(
        c.text,
        _currency,
        _irrUnit,
        legacyMinor: legacy,
      );
      if (parsed.minor != null) {
        values[c] = priceMajorText(
          parsed.minor!,
          unit == IrrUnit.toman ? 3 : 2,
        );
      }
    }
    _paint(() => _irrUnit = unit);
    // Rebuild the reference field with its new precision BEFORE changing
    // controller text, otherwise its old formatter drops the decimal point.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final entry in values.entries) {
        entry.key.text = entry.value;
      }
      _markDirty();
    });
    _markDirty();
  }
}
