part of 'loan_edit_sheet.dart';

mixin _LoanEditLogic on State<_LoanEditSheet> {
  late final TextEditingController _person;
  late final TextEditingController _amount;
  late final TextEditingController _what;
  late final TextEditingController _quantity;
  late final TextEditingController _daysAgo;
  late final TextEditingController _dueIn;
  late final TextEditingController _note;
  late LoanDirection _direction;
  late LoanKind _kind;
  bool _saving = false;
  late final FormDraft _draft;
  bool _restoring = true;
  late String _currency;
  late LoanDates _dates;
  late int _digits;
  late final String _recordId = widget.editing?.id ?? widget.store.newId();
  String? _personError;
  String? _amountError;
  String? _whatError;
  String? _quantityError;
  String? _daysError;
  String? _dueError;

  List<LoanReturn> get _myReturns => [
    for (final r in widget.returns)
      if (r.loanId == widget.editing?.id) r,
  ];

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _currency = editing?.currency ?? 'IRR';
    _digits = editing?.digits ?? 0;
    _dates = LoanDates(DateTime.now(), editing);
    _person = TextEditingController(text: editing?.person ?? '');
    _direction = editing?.direction ?? widget.initialDirection;
    _kind = editing?.kind ?? LoanKind.money;
    _amount = TextEditingController(
      text: editing != null && editing.kind == LoanKind.money
          ? moneyInput(editing.amount, _digits)
          : '',
    );
    _what = TextEditingController(
      text: editing?.kind == LoanKind.item ? (editing!.what) : '',
    );
    _quantity = TextEditingController(
      text: editing != null && editing.kind == LoanKind.item
          ? '${editing.amount}'
          : '1',
    );
    _daysAgo = TextEditingController(
      text: editing == null ? '0' : '${_dates.issueOffset}',
    );
    _dueIn = TextEditingController(
      text: editing?.due == null ? '' : '${_dates.dueOffset}',
    );
    _note = TextEditingController(text: editing?.note ?? '');
    _draft = FormDraft(
      widget.store,
      'loan:${widget.editing?.id ?? 'new'}',
      widget.editing?.toJson() ?? const {},
      {
        'person': _person,
        'amount': _amount,
        'what': _what,
        'quantity': _quantity,
        'daysAgo': _daysAgo,
        'dueIn': _dueIn,
        'note': _note,
      },
      () => {
        'recordId': _recordId,
        'currency': _currency,
        'digits': _digits,
        'direction': _direction.key,
        'kind': _kind.key,
        'anchor': _dates.anchor.toIso8601String(),
      },
    );
    unawaited(_restoreDraft());
  }

  Future<void> _restoreDraft() async {
    final body = await _draft.load();
    if (!mounted) return;
    if (body != null) {
      _draft.apply(body);
      _currency = currencyCode(body['currency']);
      _digits = moneyDigits(_currency, body['digits']);
      _direction = LoanDirection.fromKey('${body['direction']}');
      _kind = LoanKind.fromKey('${body['kind']}');
      final anchor = DateTime.tryParse('${body['anchor'] ?? ''}');
      if (anchor != null) _dates = LoanDates(anchor, widget.editing);
    }
    _draft.start();
    setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _draft.close();
    _person.dispose();
    _amount.dispose();
    _what.dispose();
    _quantity.dispose();
    _daysAgo.dispose();
    _dueIn.dispose();
    _note.dispose();
    super.dispose();
  }

  int? _int(TextEditingController controller) =>
      parseWhole(controller.text, signed: true, max: maxMoney);

  Future<void> _save() async {
    final strings = lentStrings;
    final person = _person.text.trim();
    final amount = parseMoney(_amount.text, _digits);
    final quantity = _int(_quantity);
    final days = _int(_daysAgo);
    final dueInText = _dueIn.text.trim();
    final int? dueIn = dueInText.isEmpty
        ? 0
        : parseWhole(dueInText, signed: true);

    final int total = _kind == LoanKind.money
        ? (amount ?? -1)
        : (quantity ?? -1);

    setState(() {
      _personError = person.isEmpty ? strings(context, 'personRequired') : null;
      _amountError = _kind == LoanKind.money && (amount == null || amount <= 0)
          ? amount == null
                ? strings(context, 'numberInvalid')
                : strings(context, 'zeroAmount')
          : null;
      _whatError = _kind == LoanKind.item && _what.text.trim().isEmpty
          ? strings(context, 'whatRequired')
          : null;
      _quantityError =
          _kind == LoanKind.item && (quantity == null || quantity <= 0)
          ? quantity == null
                ? strings(context, 'numberInvalid')
                : strings(context, 'zeroAmount')
          : null;
      _daysError = days == null || days < 0 || days > 365000
          ? days == null
                ? strings(context, 'numberInvalid')
                : strings(context, 'daysInvalid')
          : null;
      _dueError = dueInText.isNotEmpty && (dueIn == null)
          ? dueIn == null
                ? strings(context, 'numberInvalid')
                : strings(context, 'dueInvalid')
          : null;
    });

    if (_personError != null ||
        _amountError != null ||
        _whatError != null ||
        _quantityError != null ||
        _daysError != null ||
        _dueError != null) {
      return;
    }

    if (_myReturns.isNotEmpty &&
        widget.editing != null &&
        (_kind != widget.editing!.kind ||
            _currency != widget.editing!.currency)) {
      setState(() => _amountError = strings(context, 'unitLocked'));
      return;
    }
    // An edit may not drop the total below what has already come back.
    final totalError = LoanMath.totalError(_myReturns, total);
    if (totalError != null) {
      setState(() {
        if (_kind == LoanKind.money) {
          _amountError = strings(context, 'belowReturned');
        } else {
          _quantityError = strings(context, 'belowReturned');
        }
      });
      return;
    }

    if (_saving) return;
    setState(() => _saving = true);

    final issued = _dates.issued(days!);
    final due = _dates.due(dueInText.isEmpty ? null : dueIn);
    if (due != null && civilDaysBetween(issued, due)! < 0) {
      setState(() {
        _saving = false;
        _dueError = strings(context, 'dueBeforeIssue');
      });
      return;
    }

    final body = <String, Object?>{
      'v': 2,
      'currency': _currency,
      'currencyDecimals': _digits,
      'direction': _direction.key,
      'person': person,
      'type': _kind.key,
      'amount': total,
      'what': _kind == LoanKind.item ? _what.text.trim() : '',
      'issued': issued,
      'due': due,
      'note': _note.text.trim(),
    };
    final id = _recordId;
    final saved = await storeWrite(context, () async {
      final old = await widget.store.get('loan', id);
      if (old != null) {
        final fresh = Loan.fromBody(id, old);
        final history = (await widget.store.list(
          'return',
        )).map(LoanReturn.fromRecord).where((r) => r.loanId == id).toList();
        if (history.isNotEmpty &&
            (_kind != fresh.kind ||
                _currency != fresh.currency ||
                _digits != fresh.digits)) {
          throw StateError('Units changed');
        }
        if (LoanMath.totalError(history, total) != null) {
          throw StateError('Total below returned');
        }
      }
      await widget.store.put('loan', id, {...?old, ...body});
    });
    if (!mounted) return;
    if (!saved) setState(() => _saving = false);
    if (saved) {
      try {
        await _draft.clear();
      } catch (_) {
        /* Saved record remains authoritative. */
      }
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop();
      }
    }
  }
}
