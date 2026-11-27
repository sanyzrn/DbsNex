part of 'medicine_editor.dart';

/// Saving, checking and leaving: the half of the editor that is not the
/// form itself.
extension _MedicineEditorActions on _MedicineEditorSheetState {
  // -------------------------------------------------------------- saving

  Future<void> _save() async {
    if (_session.busy || _session.loading || _session.failed) {
      return;
    }
    final expiry = MedicineParse.expiry(_expiry.text);
    if (_name.text.trim().isEmpty ||
        _badNumber(_quantity, minimum: 0) ||
        _badNumber(_doseUnits, minimum: 1) ||
        _badNumber(_refill, minimum: 0) ||
        _timeOverflow ||
        _time.text.trim().isNotEmpty && _addTime() == null ||
        expiry == MedicineParse.invalid ||
        _badEveryDays ||
        _badWarnDays ||
        _badStart ||
        _badEnd ||
        _badScheduleOrder) {
      _paint(() {
        _showErrors = true;
        _more = true;
      });
      return;
    }
    if (_time.text.trim().isNotEmpty) _rememberTime(_time.text);
    _paint(() => _session.busy = true);
    try {
      final records = await widget.store.list(MedicineModels.medicine);
      final duplicate = records.any(
        (r) =>
            r.id != widget.existing?.id &&
            !MedicineModels.readArchived(r.body) &&
            MedicineLogic.sameName(
              MedicineModels.readString(r.body, 'name'),
              _name.text,
            ),
      );
      if (!mounted) {
        return;
      }
      if (duplicate &&
          await MedicineDialogs.askDuplicate(
                context,
                medicineStrings,
                _name.text.trim(),
              ) !=
              true) {
        return;
      }
      if (!mounted) {
        return;
      }
      await _saveBody();
    } catch (_) {
      _saveError();
    } finally {
      if (mounted) {
        _paint(() => _session.busy = false);
      }
    }
  }

  Future<void> _saveBody() async {
    final body = MedicineModels.medicineBody(
      name: _name.text,
      strength: _strength.text,
      packageUnit: _packageUnit.text,
      instructions: _instructions.text,
      times: _times,
      days: _days.text,
      purpose: _purpose.text,
      quantity: MedicineParse.count(_quantity.text),
      doseUnits: MedicineParse.count(_doseUnits.text),
      expiresAt: MedicineParse.expiry(_expiry.text),
      refillThreshold: MedicineParse.count(_refill.text),
      archived: MedicineModels.readArchived(_from),
      person: _person.text,
      weekdays: _weekdays.toList()..sort(),
      everyDays: MedicineParse.count(_every.text),
      startsOn: MedicineParse.day(_start.text),
      endsOn: MedicineParse.day(_end.text),
      warnDays: MedicineParse.count(_warn.text),
      hardToFind: _hardToFind,
    );
    final keys = _session.editedKeys(body, {
      'name': ['name'],
      'strength': ['strength'],
      'package': ['package'],
      'instructions': ['instructions'],
      'days': ['days'],
      'purpose': ['purpose'],
      'quantity': ['quantity'],
      'doseUnits': ['doseUnits'],
      'times': ['times'],
      'expiresAt': ['expiry'],
      'refillThreshold': ['refill'],
      'person': ['person'],
      'weekdays': ['weekdays'],
      'everyDays': ['everyDays'],
      'startsOn': ['startsOn'],
      'endsOn': ['endsOn'],
      'warnDays': ['warnDays'],
      'hardToFind': ['hardToFind'],
    });
    await MedicineRepository.save(
      widget.store,
      _session.recordId,
      body,
      keys,
      existing: widget.existing != null,
    );
    await _session.draft.clear();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  DateTime? get _startDay => MedicineParse.day(_start.text);
  DateTime? get _endDay => MedicineParse.day(_end.text);

  bool get _badEveryDays {
    final text = _every.text.trim();
    if (text.isEmpty) {
      return false;
    }
    final parsed = MedicineParse.count(text);
    return parsed == null ||
        parsed < 2 ||
        parsed > MedicineModels.everyDaysLimit;
  }

  /// Both day rules written at once: the weekday chips and an every-N-days
  /// number. The routine reads the weekday set (README → Decisions), so the
  /// editor says so rather than letting both look equally alive.
  bool get _bothDayRules {
    if (_weekdays.isEmpty) {
      return false;
    }
    final parsed = MedicineParse.count(_every.text);
    return parsed != null && parsed >= 2;
  }

  bool get _badWarnDays {
    final text = _warn.text.trim();
    if (text.isEmpty) {
      return false;
    }
    final parsed = MedicineParse.count(text);
    return parsed == null || parsed > 3650;
  }

  bool get _badStart => _startDay == MedicineParse.invalid;
  bool get _badEnd => _endDay == MedicineParse.invalid;

  bool get _badScheduleOrder {
    final start = _startDay;
    final end = _endDay;
    if (start == null ||
        end == null ||
        start == MedicineParse.invalid ||
        end == MedicineParse.invalid) {
      return false;
    }
    return end.isBefore(start);
  }

  void _toggleWeekday(int day) {
    _paint(() {
      _dirty = true;
      if (!_weekdays.remove(day)) {
        _weekdays.add(day);
      }
    });
    _session.changed();
  }

  void _setHardToFind(bool value) {
    _paint(() {
      _dirty = true;
      _hardToFind = value;
    });
    _session.changed();
  }

  /// A routine time as written, or null when it is not one.
  String? _addTime() => MedicineLogic.normalizeTime(_time.text);
  bool get _timeOverflow =>
      _addTime() != null &&
      !_times.contains(_addTime()) &&
      _times.length >= MedicineModels.timesLimit;

  /// A written number that is not whole, or below the minimum. An empty
  /// field is fine: the person keeps that number themselves.
  bool _badNumber(TextEditingController field, {required int minimum}) {
    final text = field.text.trim();
    if (text.isEmpty) {
      return false;
    }
    final parsed = MedicineParse.count(text);
    return parsed == null || parsed < minimum;
  }

  // -------------------------------------------------------------- times

  void _rememberTime(String written) {
    final normalized = MedicineLogic.normalizeTime(written);
    if (normalized == null ||
        _times.contains(normalized) ||
        _times.length >= MedicineModels.timesLimit) {
      _paint(() {}); // Show the invalid-time helper.
      return;
    }
    _paint(() {
      _dirty = true;
      _times = [..._times, normalized]..sort();
      _time.clear();
    });
    _session.changed();
  }

  // ------------------------------------------------------------ leaving

  Future<void> _maybePop() async {
    if (_session.busy) {
      return;
    }
    if (!_dirty) {
      _paint(() => _session.busy = true);
      final kept = await _session.draft.finish();
      if (!mounted) return;
      if (kept) {
        Navigator.of(context).pop();
      } else {
        if (!_session.failed) _session.draft.resume();
        _paint(() => _session.busy = false);
        _saveError();
      }
      return;
    }
    final leave = await MedicineDialogs.confirmDiscard(
      context,
      medicineStrings,
    );
    if (leave == true && mounted) {
      _paint(() => _session.busy = true);
      if (await _session.discard() && mounted) {
        Navigator.of(context).pop();
      } else {
        if (!_session.failed) _session.draft.resume();
        _paint(() => _session.busy = false);
        _saveError();
      }
    }
  }

  Future<void> _keepDraft() async {
    if (_session.busy || _session.loading || _session.failed) {
      return;
    }
    _paint(() => _session.busy = true);
    final saved = await _session.draft.finish();
    if (!mounted) {
      return;
    }
    if (saved) {
      Navigator.of(context).pop();
    } else {
      _session.draft.resume();
      _paint(() => _session.busy = false);
      _saveError();
    }
  }

  void _saveError() {
    if (!mounted) {
      return;
    }
    NexBannerHost.of(context)?.show(
      kind: NexBannerKind.failed,
      message: medicineStrings(context, 'saveFailed'),
    );
  }
}
