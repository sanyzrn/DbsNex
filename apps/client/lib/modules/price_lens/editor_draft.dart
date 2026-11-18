part of 'option_editor.dart';

extension _OfferDraft on _OptionEditorSheetState {
  Future<void> _loadDraft() async {
    if (_loading) return;
    _loading = _draft != null;
    final data = await _draft?.load();
    if (widget.existing?.source != null &&
        !priceSchemaKnown(widget.existing!.source!)) {
      if (mounted) {
        _paint(() {
          _loading = false;
          _loadFailed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    if (_draft?.loadFailed == true) {
      _paint(() {
        _loading = false;
        _loadFailed = true;
      });
      return;
    }
    if (data != null) {
      _draft!.apply(data);
      if (data['recordId'] is String) _id = data['recordId'] as String;
      if (data['currency'] is String) {
        _currency = priceCurrencyOf(data['currency'] as String) ?? _currency;
      }
      if (data['unit'] is String &&
          priceUnitOf(data['unit'] as String) != null) {
        _unitKey = data['unit'] as String;
      }
      _irrUnit = IrrUnit.fromKey(data['irrUnit']);
      _discountKind =
          DiscountKind.values
              .where((v) => v.name == data['discountKind'])
              .firstOrNull ??
          DiscountKind.none;
      _details = data['details'] == true;
    }
    _paint(() {
      _loading = false;
      _loadFailed = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializing = false;
      _draft?.start();
    });
  }
}
