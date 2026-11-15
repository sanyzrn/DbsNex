part of 'warranty_editor.dart';

/// Saving and leaving, kept apart from the form's own layout: the save
/// completes inside the editor (so no Save button can be left behind on
/// another screen), keeps its words on failure, and sets the reminder the
/// person was offered while they were writing.
extension _WarrantyEditorSave on _WarrantyEditorSheetState {
  Future<void> _save() async {
    if (_session.busy || _session.loading || _session.failed) {
      return;
    }
    final purchase = _purchase;
    final end = _coverageEnd;
    final bothWays =
        _duration.text.trim().isNotEmpty && _endDate.text.trim().isNotEmpty;

    if (_product.text.trim().isEmpty ||
        _purchaseBad ||
        end == null ||
        end == WarrantyParse.invalid ||
        bothWays ||
        _amountBad) {
      _paint(() {
        _showErrors = true;
        if (_amountBad) _more = true;
      });
      return;
    }
    if (!WarrantyLogic.endAfterPurchase(purchase!, end)) {
      _paint(() => _showErrors = true);
      return;
    }

    final months = WarrantyParse.count(_duration.text);
    final body = WarrantyModels.warrantyBody(
      product: _product.text,
      category: _category.text,
      brand: _brand.text,
      model: _model.text,
      serial: _serial.text,
      merchant: _merchant.text,
      receiptRef: _receiptRef.text,
      coverageType: _coverageType.text,
      note: _note.text,
      purchasedAt: purchase,
      coverageEnd: end,
      coverKind: _coverKind,
      company: _company.text,
      supportPhone: _supportPhone.text,
      cardNumber: _cardNumber.text,
      registryOwner: _registry,
      durationMonths: (months != null && months > 0) ? months : null,
      amountRials: WarrantyParse.rials(_amount.text, inTomans: _inTomans),
      archived: WarrantyModels.readArchived(_from),
    );
    final keys = _session.editedKeys(body, {
      'product': ['product'],
      'category': ['category'],
      'brand': ['brand'],
      'model': ['model'],
      'serial': ['serial'],
      'merchant': ['merchant'],
      'company': ['company'],
      'supportPhone': ['supportPhone'],
      'cardNumber': ['cardNumber'],
      'coverKind': ['coverKind'],
      'registryOwner': ['registry'],
      'coverageType': ['coverageType'],
      'receiptRef': ['receiptRef'],
      'note': ['note'],
      'purchasedAt': ['purchase'],
      'coverageEnd': ['purchase', 'duration', 'end'],
      'durationMonths': ['duration', 'end'],
      'amountRials': ['amount', 'inTomans'],
    });
    _paint(() => _session.busy = true);
    try {
      await WarrantyRepository.save(
        widget.store,
        _session.recordId,
        body,
        keys,
        existing: widget.existing != null,
      );
      await _session.draft.clear();
      if (!mounted) return;
      await _setReminder(end);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      _saveError();
    } finally {
      if (mounted) {
        _paint(() => _session.busy = false);
      }
    }
  }

  /// Sets the one-time alert offered beside the end date. A failure here is
  /// reported and never hides the fact that the purchase itself was saved.
  Future<void> _setReminder(DateTime end) async {
    final moment = _reminderMoment;
    if (!widget.store.remindersEnabled || !_remindOn || moment == null) {
      return;
    }
    final messenger = NexBannerHost.of(context);
    final failedText = warrantyStrings(context, 'reminderNotSet');
    var ok = false;
    try {
      final id = _session.recordId;
      ok = await widget.store.setReminder(
        // The same key the shared control uses for this purchase, so the
        // reminder set here and the one cleared there are the same alarm.
        '${WarrantyModels.warranty}:$id',
        sourceKind: WarrantyModels.warranty,
        sourceId: id,
        at: moment,
        title: warrantyStrings(context, 'reminderTitleText'),
        body: warrantyStrings(context, 'reminderBody', {
          'name': _product.text.trim(),
          'date': WarrantyFields.dayLabel(context, end),
        }),
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger?.show(kind: NexBannerKind.failed, message: failedText);
    }
  }

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
    final leave = await WarrantyDialogs.confirmDiscard(
      context,
      warrantyStrings,
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
      message: warrantyStrings(context, 'saveFailed'),
    );
  }
}
