part of 'loan_edit_sheet.dart';

mixin _LoanEditLogic on State<_LoanEditSheet> {
  late final TextEditingController _person;
  late final TextEditingController _amount;
  late final TextEditingController _what;
  late final TextEditingController _quantity;
  late final TextEditingController _issueDate;
  late final TextEditingController _dueDate;
  late final TextEditingController _note;
  late LoanDirection _direction;
  late LoanKind _kind;
  bool _saving = false;
  late final FormDraft _draft;
  bool _restoring = true;
  late String _currency;
  late int _digits;
  late final String _recordId = widget.editing?.id ?? widget.store.newId();
  String? _personError;
  String? _amountError;
  String? _whatError;
  String? _quantityError;
  String? _issueError;
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
    _issueDate = TextEditingController(
      text: dateEntryText(editing?.issued ?? civilDateKey(DateTime.now())),
    );
    _dueDate = TextEditingController(
      text: editing?.due == null ? '' : dateEntryText(editing!.due!),
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
        'issueDate': _issueDate,
        'dueDate': _dueDate,
        'note': _note,
      },
      () => {
        'recordId': _recordId,
        'currency': _currency,
        'digits': _digits,
        'direction': _direction.key,
        'kind': _kind.key,
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
      _migrateLegacyDateDraft(body);
    }
    _draft.start();
    setState(() => _restoring = false);
  }

  /// Drafts written before absolute date entry stored day offsets against an
  /// open-time anchor. Bring those onto the calendar as the dates they
  /// meant, so a checkpoint survives the upgrade.
  void _migrateLegacyDateDraft(Map<String, Object?> body) {
    final anchor = DateTime.tryParse('${body['anchor'] ?? ''}');
    if (anchor == null) return;
    final daysAgo = body['daysAgo'];
    if (daysAgo is String) {
      final offset = int.tryParse(daysAgo);
      if (offset != null) {
        _issueDate.text = dateEntryText(shiftCivilDate(anchor, -offset));
      }
    }
    final dueIn = body['dueIn'];
    if (dueIn is String) {
      final trimmed = dueIn.trim();
      if (trimmed.isEmpty) {
        _dueDate.clear();
      } else {
        final offset = int.tryParse(trimmed);
        if (offset != null) {
          _dueDate.text = dateEntryText(shiftCivilDate(anchor, offset));
        }
      }
    }
  }

  @override
  void dispose() {
    _draft.close();
    _person.dispose();
    _amount.dispose();
    _what.dispose();
    _quantity.dispose();
    _issueDate.dispose();
    _dueDate.dispose();
    _note.dispose();
    super.dispose();
  }

  int? _int(TextEditingController controller) =>
      parseWhole(controller.text, signed: true, max: maxMoney);

  /// A stored date the field still shows untouched is kept exactly, even
  /// when it is older than the typed-entry range (a legacy record dated a
  /// thousand years back, say).
  String? _unchangedDate(String written, String? stored) =>
      stored != null && dateEntryText(stored) == written ? stored : null;

  Future<void> _save() async {
    final strings = lentStrings;
    final person = _person.text.trim();
    final amount = parseMoney(_amount.text, _digits);
    final quantity = _int(_quantity);
    final issueWritten = _issueDate.text.trim();
    final dueWritten = _dueDate.text.trim();
    final issue =
        parseDateEntry(issueWritten) ??
        _unchangedDate(issueWritten, widget.editing?.issued);
    final due =
        parseDateEntry(dueWritten) ??
        _unchangedDate(dueWritten, widget.editing?.due);

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
      _issueError = issue == null ? strings(context, 'dateInvalid') : null;
      _dueError = dueWritten.isNotEmpty && due == null
          ? strings(context, 'dateInvalid')
          : null;
    });

    if (_personError != null ||
        _amountError != null ||
        _whatError != null ||
        _quantityError != null ||
        _issueError != null ||
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

    // Null only means an unparseable pair, which the construction above
    // rules out; treating it as "not before" keeps the guard total.
    if (due != null && (civilDaysBetween(issue!, due) ?? 0) < 0) {
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
      'issued': issue,
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
