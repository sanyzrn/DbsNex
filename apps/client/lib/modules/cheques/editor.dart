import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'editor_options.dart';
import 'model.dart';
import 'reminders.dart';
import 'repository.dart';
import 'strings.dart';
import 'privacy.dart';
import 'values.dart';
import 'widgets.dart';
import 'draft_guard.dart';
import 'amount_field.dart';
import 'irr_unit.dart';

part 'editor_body.dart';

class ChequeEditor extends StatefulWidget {
  const ChequeEditor({super.key, required this.repo, this.cheque});
  final ChequeRepository repo;
  final Cheque? cheque;
  @override
  State<ChequeEditor> createState() => _ChequeEditorState();
}

class _ChequeEditorState extends State<ChequeEditor> {
  late final _fields = <String, TextEditingController>{
    for (final k in ['party', 'bank', 'account', 'number', 'sayad', 'note'])
      k: TextEditingController(text: widget.cheque?.text(k) ?? ''),
    'amount': TextEditingController(
      text: widget.cheque?.face == null
          ? ''
          : amountForEdit(widget.cheque!.face!, _unit),
    ),
  };
  late String _unit =
      widget.cheque?.unit == 'toman' &&
          widget.cheque!.face! % BigInt.from(10) != BigInt.zero
      ? 'rial'
      : widget.cheque?.unit ?? 'toman';
  late String _direction = widget.cheque?.direction ?? 'outgoing',
      _purpose = widget.cheque?.purpose ?? 'payment';
  late String _sayadState = widget.cheque?.text('sayadState') ?? 'unknown';
  late DateTime? _day = widget.cheque?.actionDay;
  late bool _details = widget.cheque != null,
      _remind = widget.cheque?.raw['remind'] == true;
  late Set<int> _days = widget.cheque == null
      ? {3, 0}
      : Set<int>.from(widget.cheque!.raw['reminderDays'] as List);
  late int _minutes = widget.cheque?.raw['minutes'] as int? ?? 540;
  late String _id = widget.cheque?.id ?? widget.repo.store.newId();
  late final _draft = NexModuleFormDraft(
    widget.repo.store,
    'cheque:${widget.cheque?.id ?? 'new'}',
    widget.cheque?.raw ?? const {},
    _fields,
    () => {
      'recordId': _id,
      'unit': _unit,
      'direction': _direction,
      'purpose': _purpose,
      'day': _day == null ? '' : chequeDayKey(_day!),
      'sayadState': _sayadState,
      'details': _details,
      'remind': _remind,
      'reminderDays': _days.toList(),
      'minutes': _minutes,
    },
  );
  bool _loading = true, _failed = false, _saving = false;
  bool _reading = false, _amountQueued = false;
  String? _error;
  Cheque? _committed;
  bool get locked => widget.cheque?.locked == true;
  @override
  void initState() {
    super.initState();
    _fields['amount']!.addListener(_amountChanged);
    unawaited(_load());
  }

  // The reference groups the controller during dependency changes. Schedule
  // the secondary conversion after build, so locale/unit changes remain safe.
  void _amountChanged() {
    if (_amountQueued) return;
    _amountQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _amountQueued = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    if (_reading) return;
    _reading = true;
    final data = await _draft.load();
    _reading = false;
    if (!mounted) return;
    if (_draft.loadFailed) {
      setState(() {
        _failed = true;
        _loading = false;
      });
      return;
    }
    if (data != null) {
      _draft.apply(data);
      final id = data['recordId'];
      if (widget.cheque == null &&
          id is String &&
          RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)) {
        _id = id;
      }
      if (['rial', 'toman'].contains(data['unit'])) {
        _unit = data['unit'] as String;
      }
      if (['incoming', 'outgoing'].contains(data['direction'])) {
        _direction = data['direction'] as String;
      }
      if (['payment', 'guarantee'].contains(data['purpose'])) {
        _purpose = data['purpose'] as String;
      }
      _day = chequeDay(data['day']);
      if (['unknown', 'todo', 'checked'].contains(data['sayadState'])) {
        _sayadState = data['sayadState'] as String;
      }
      _details = data['details'] == true;
      _remind = data['remind'] == true;
      if (data['minutes'] is int &&
          (data['minutes'] as int) >= 0 &&
          (data['minutes'] as int) < 1440) {
        _minutes = data['minutes'] as int;
      }
      if (data['reminderDays'] is List) {
        _days = (data['reminderDays'] as List)
            .whereType<int>()
            .where([0, 1, 3, 7, 14, 30].contains)
            .toSet();
      }
    }
    _draft.start();
    setState(() {
      _loading = false;
      _failed = false;
    });
  }

  @override
  void dispose() {
    _fields['amount']!.removeListener(_amountChanged);
    _draft.close();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _change(String key, Object value) {
    setState(() {
      switch (key) {
        case 'details':
          _details = value as bool;
        case 'remind':
          _remind = value as bool;
        case 'reminderDays':
          _days = value as Set<int>;
        case 'minutes':
          _minutes = value as int;
        case 'sayadState':
          _sayadState = value as String;
      }
    });
    _draft.changed();
  }

  void _unitChange(String unit) {
    if (unit == _unit) return;
    final rial = enteredAmount(_fields['amount']!.text, _unit);
    if (rial != null &&
        unit == 'toman' &&
        rial % BigInt.from(10) != BigInt.zero) {
      setState(() => _error = chequeStrings(context, 'unitError'));
      return;
    }
    setState(() {
      if (rial != null) _fields['amount']!.text = amountForEdit(rial, unit);
      _unit = unit;
      _error = null;
    });
    _draft.changed();
  }

  Future<void> _pickDay() async {
    final picked = await nexPickModuleDate(
      context,
      initial: _day ?? DateTime.now(),
      first: DateTime(1900),
      last: DateTime(2100, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _day = picked);
      _draft.changed();
    }
  }

  Future<void> _save() async {
    if (_loading || _saving || _failed) return;
    setState(() => _saving = true);
    try {
      _committed ??= await widget.repo.save(_id, widget.cheque?.raw, {
        for (final key in ['party', 'bank', 'account', 'number', 'note'])
          key: _fields[key]!.text.trim(),
        'sayad': chequeDigits(_fields['sayad']!.text.trim()),
        'direction': _direction,
        'purpose': _purpose,
        'amountRial':
            editableAmount(
              _fields['amount']!.text,
              _unit,
              original: widget.cheque?.face,
            )?.toString() ??
            '',
        'unit': _unit,
        'due': _purpose == 'payment' && _day != null ? chequeDayKey(_day!) : '',
        'followUp': _purpose == 'guarantee' && _day != null
            ? chequeDayKey(_day!)
            : '',
        'sayadState': _sayadState,
        'sayadCheckedDay': _sayadState == 'checked'
            ? (widget.cheque?.text('sayadState') == 'checked'
                  ? widget.cheque!.text('sayadCheckedDay')
                  : chequeDayKey(DateTime.now()))
            : '',
        'remind': _remind,
        'reminderDays': _days.toList()..sort(),
        'minutes': _minutes,
      });
      if (!await _draft.clear()) {
        if (mounted) {
          setState(() {
            _error = chequeStrings(context, 'cleanup');
            _saving = false;
          });
        }
        return;
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      var ok = true;
      try {
        ok = await armCheque(widget.repo.store, _committed!, l10n);
      } catch (_) {
        ok = false;
      }
      if (!mounted) return;
      if (!ok) {
        nexShowBanner(
          context,
          message: chequeStrings(context, 'remindError'),
          kind: NexBannerKind.failed,
        );
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = chequeStrings(
            context,
            e is ChequeFailure ? e.code : 'saveError',
          );
        });
      }
    }
  }

  void _update(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => _body(context);
}
