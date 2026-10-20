part of 'gold_form.dart';

mixin _GoldFormLogic on State<GoldForm> {
  final _weight = TextEditingController();
  final _gross = TextEditingController();
  final _rate = TextEditingController();
  final _makingPercent = TextEditingController();
  final _makingPerGram = TextEditingController();
  final _makingFixed = TextEditingController();
  final _profit = TextEditingController();
  final _vat = TextEditingController();
  final _commission = TextEditingController();
  final _shopQuote = TextEditingController();

  final List<GoldExtraControllers> _extras = [];

  int _fineness = 750;
  int _rateRef = 750;
  GoldMakingMode _mode = GoldMakingMode.percent;

  /// True while the form is being prefilled during `initState`: the
  /// parent may not be asked to rebuild while it is itself building this
  /// form's subtree, so the notification is delivered after the frame.
  bool _suppressParentNotify = false;
  GoldProfitBase _profitBase = GoldProfitBase.metalAndMaking;
  bool _commissionTaxable = true;
  FormDraft? _draft;
  bool _restoring = true;
  bool _draftLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _profit.text = '7';
    _vat.text = '10';
    for (final controller in _controllers) {
      controller.addListener(_changed);
    }
    final initial = widget.initialQuote;
    if (initial != null) {
      _suppressParentNotify = true;
      loadQuote(initial);
      _suppressParentNotify = false;
      // A fresh form starts empty — its input is invalid, which is what the
      // parent already assumes. A prefilled one delivers its input once the
      // mounting frame is done.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onInputChanged(buildInput());
      });
    }
    _draft = _newDraft(initial);
    unawaited(_restoreGoldDraft(this, initial: true));
  }

  List<TextEditingController> get _controllers => [
    _weight,
    _gross,
    _rate,
    _makingPercent,
    _makingPerGram,
    _makingFixed,
    _profit,
    _vat,
    _commission,
    _shopQuote,
  ];

  @override
  void dispose() {
    _draft?.close();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final extra in _extras) {
      extra.label.dispose();
      extra.amount.dispose();
    }
    super.dispose();
  }

  /// Fills the form from a saved quote, for editing and re-saving.
  void loadQuote(GoldQuote quote) {
    final input = quote.input;
    _weight.text = inputScaled(input.weightMg, 3);
    if (input.grossWeightMg > 0) {
      _gross.text = inputScaled(input.grossWeightMg, 3);
    }
    _rate.text = inputScaled(input.rateCentiPerG, 2);
    _fineness = input.finenessPpt;
    _rateRef = input.rateRefPpt;
    _mode = input.makingMode;
    _profitBase = input.profitBase;
    _commissionTaxable = input.commissionTaxable;
    if (input.makingMode == GoldMakingMode.percent ||
        input.makingMode == GoldMakingMode.mixed) {
      _makingPercent.text = inputScaled(input.makingPercentBp, 2);
    }
    if (input.makingMode == GoldMakingMode.perGram ||
        input.makingMode == GoldMakingMode.mixed) {
      _makingPerGram.text = inputScaled(input.makingPerGramCenti, 2);
    }
    if (input.makingMode == GoldMakingMode.fixed) {
      _makingFixed.text = inputScaled(input.makingFixedRial, 1);
    }
    _profit.text = inputScaled(input.profitBp, 2);
    _vat.text = inputScaled(input.vatBp, 2);
    if (input.commissionRial > 0) {
      _commission.text = inputScaled(input.commissionRial, 1);
    }
    if (input.shopQuoteRial > 0) {
      _shopQuote.text = inputScaled(input.shopQuoteRial, 1);
    }
    for (final extra in _extras) {
      extra.label.dispose();
      extra.amount.dispose();
    }
    _extras.clear();
    for (final (label, amount) in input.extras) {
      _addExtra(label: label, amountCenti: amount * 10, notify: false);
    }
    _changed();
  }

  /// Empties the form back to a fresh estimate.
  void clear() {
    for (final controller in _controllers) {
      controller.clear();
    }
    for (final extra in _extras) {
      extra.label.dispose();
      extra.amount.dispose();
    }
    setState(() {
      _extras.clear();
      _fineness = 750;
      _rateRef = 750;
      _mode = GoldMakingMode.percent;
      _profit.text = '7';
      _vat.text = '10';
    });
    _changed();
  }

  void _changed() {
    _draft?.changed();
    if (mounted) setState(() {});
    if (!_suppressParentNotify) {
      widget.onInputChanged(buildInput());
    }
  }

  /// The input the form holds right now, or null while it is invalid.
  GoldInput? buildInput({bool forBudget = false}) {
    if (_restoring || _draftLoadFailed) return null;
    int? read(
      TextEditingController c,
      int scale,
      int max, {
      bool required = false,
    }) {
      if (c.text.trim().isEmpty) return required ? null : 0;
      final (value, problem) = parseScaledDetailed(c.text, scale);
      return problem == null && value != null && value >= 0 && value <= max
          ? value
          : null;
    }

    // For a budget the weight is the unknown: a placeholder gram stands in,
    // and neither a gross weight nor the seller's quote (both about a piece
    // that has not been chosen) takes part.
    final weight = forBudget
        ? 1000
        : read(_weight, 3, GoldInput.maxWeightMg, required: true);
    final gross = forBudget ? 0 : read(_gross, 3, GoldInput.maxGrossMg);
    final rate = read(_rate, 2, GoldInput.maxRateCenti, required: true);
    final percent =
        _mode == GoldMakingMode.percent || _mode == GoldMakingMode.mixed
        ? read(_makingPercent, 2, GoldInput.maxPercentBp)
        : 0;
    final perGram =
        _mode == GoldMakingMode.perGram || _mode == GoldMakingMode.mixed
        ? read(_makingPerGram, 2, GoldInput.maxPerGramCenti)
        : 0;
    final fixed = _mode == GoldMakingMode.fixed
        ? read(_makingFixed, 2, GoldInput.maxAmountRial * 10)
        : 0;
    final profit = read(_profit, 2, GoldInput.maxPercentBp);
    final vat = read(_vat, 2, GoldInput.maxPercentBp);
    final commission = read(_commission, 2, GoldInput.maxAmountRial * 10);
    final quote = forBudget
        ? 0
        : read(_shopQuote, 2, GoldInput.maxAmountRial * 10);
    if ([
      weight,
      gross,
      rate,
      percent,
      perGram,
      fixed,
      profit,
      vat,
      commission,
      quote,
    ].contains(null)) {
      return null;
    }
    final extras = <(String, int)>[];
    for (final extra in _extras) {
      final amount = read(extra.amount, 2, GoldInput.maxAmountRial * 10);
      if (amount == null || extra.label.text.trim().isEmpty) return null;
      extras.add((extra.label.text.trim(), _toRial(amount)));
    }
    final input = GoldInput(
      weightMg: weight!,
      grossWeightMg: gross!,
      finenessPpt: _fineness,
      rateCentiPerG: rate!,
      rateRefPpt: _rateRef,
      makingMode: _mode,
      makingPercentBp: percent!,
      makingPerGramCenti: perGram!,
      makingFixedRial: _toRial(fixed!),
      profitBp: profit!,
      vatBp: vat!,
      commissionRial: _toRial(commission!),
      profitBase: _profitBase,
      commissionTaxable: _commissionTaxable,
      extras: extras,
      shopQuoteRial: _toRial(quote!),
    );
    return input.problems().isEmpty ? input : null;
  }

  /// Puts a weight (milligrams) into the weight field, as if typed.
  void setWeightMg(int milligrams) {
    _weight.text = inputScaled(milligrams, 3);
  }

  void _addExtra({String label = '', int amountCenti = 0, bool notify = true}) {
    final amountController = TextEditingController(
      text: amountCenti == 0 ? '' : inputScaled(amountCenti, 2),
    );
    amountController.addListener(_changed);
    setState(() {
      _extras.add(
        GoldExtraControllers(
          TextEditingController(text: label)..addListener(_changed),
          amountController,
        ),
      );
    });
    if (notify) _changed();
  }

  void _removeExtra(int index) {
    setState(() {
      final removed = _extras.removeAt(index);
      removed.label.dispose();
      removed.amount.dispose();
    });
    _changed();
  }

  Map<String, TextEditingController> get _fields => {
    'weight': _weight,
    'gross': _gross,
    'rate': _rate,
    'makingPercent': _makingPercent,
    'makingPerGram': _makingPerGram,
    'makingFixed': _makingFixed,
    'profit': _profit,
    'vat': _vat,
    'commission': _commission,
    'shopQuote': _shopQuote,
    ...widget.metadata,
  };
  FormDraft _newDraft(GoldQuote? quote) => FormDraft(
    widget.store,
    'quote:${quote?.id ?? 'new'}',
    quote?.toRecord() ?? const {},
    _fields,
    () => {
      'recordId': widget.recordId,
      'fineness': _fineness,
      'rateRef': _rateRef,
      'mode': _mode.name,
      'profitBase': _profitBase.name,
      'commissionTaxable': _commissionTaxable,
      'extras': [
        for (final e in _extras)
          {'label': e.label.text, 'amount': e.amount.text},
      ],
    },
  );
  bool get canDiscard => !_restoring;
  void _beginRestore() {
    setState(() => _restoring = true);
  }

  void _draftReadError() {
    setState(() {
      _restoring = false;
      _draftLoadFailed = true;
    });
    widget.onInputChanged(null);
  }

  void _completeRestore() {
    setState(() {
      _restoring = false;
      _draftLoadFailed = false;
    });
    _changed();
  }

  Future<bool> discardDraft() async {
    if (!await _draft!.clear()) {
      if (!_draftLoadFailed) _draft!.resume();
      return false;
    }
    if (!mounted) return true;
    setState(() {
      _restoring = false;
      _draftLoadFailed = false;
    });
    clear();
    _profitBase = GoldProfitBase.metalAndMaking;
    _commissionTaxable = true;
    for (final controller in widget.metadata.values) {
      controller.clear();
    }
    widget.metadata['quoteDate']?.text = isoDay(DateTime.now());
    _draft = _newDraft(null)..start();
    _changed();
    return true;
  }

  Future<void> markSaved(GoldQuote quote) async {
    await _draft!.clear();
    if (!mounted) return;
    _draft = _newDraft(quote)..start();
  }
}
