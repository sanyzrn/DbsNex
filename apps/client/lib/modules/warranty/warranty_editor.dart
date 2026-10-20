import 'dart:async';
import 'editor_checkpoint.dart';
import 'warranty_repository.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'nex_text_field.dart';
import 'warranty_dialogs.dart';
import 'warranty_fields.dart';
import 'warranty_logic.dart';
import 'warranty_models.dart';
import 'warranty_parse.dart';
import 'warranty_editor_fields.dart';
import 'warranty_strings.dart';

part 'warranty_editor_body.dart';

/// What the editor hands back: a body ready to store, and the record it
/// belongs to when it is an edit of one that exists.
class WarrantyDraft {
  const WarrantyDraft({this.id, required this.body});

  final String? id;
  final Map<String, Object?> body;
}

/// The one form this module has: a purchase and its coverage, exactly as
/// the person knows them. The coverage comes either as a duration in
/// months — computed to its end date in front of them — or as the end
/// date itself; never from a country-wide guess. The receipt is typed as
/// text, and the form says so.
///
/// Leaving with unsaved words asks first, so a pull at the sheet or the
/// back gesture cannot throw away what has been written.
class WarrantyEditorSheet extends StatefulWidget {
  const WarrantyEditorSheet({super.key, required this.store, this.existing});

  final NexModuleStore store;
  final ModuleRecord? existing;

  @override
  State<WarrantyEditorSheet> createState() => _WarrantyEditorSheetState();
}

class _WarrantyEditorSheetState extends State<WarrantyEditorSheet> {
  late final Map<String, Object?> _from;
  late final TextEditingController _product;
  late final TextEditingController _category;
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _serial;
  late final TextEditingController _merchant;
  late final TextEditingController _purchaseDate;
  final _duration = TextEditingController();
  final _endDate = TextEditingController();
  late final TextEditingController _coverageType;
  late final TextEditingController _receiptRef;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  /// Whether the amount is typed in tomans (true) or rials (false).
  bool _inTomans = false;
  late final EditorCheckpoint _session;
  bool _dirty = false;
  bool _showErrors = false;
  // A new purchase asks the product, the day and the coverage; who made it,
  // where it was bought, the serial, the receipt, the price and a note wait
  // behind one button. A saved one, a draft with something there, or a
  // refused save opens them.
  bool _more = false;

  bool get _moreOpen =>
      _more ||
      widget.existing != null ||
      [
        _category,
        _brand,
        _model,
        _serial,
        _merchant,
        _receiptRef,
        _amount,
        _note,
      ].any((c) => c.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _from = widget.existing?.body ?? const {};
    _product = TextEditingController(
      text: WarrantyModels.readString(_from, 'product'),
    );
    _category = TextEditingController(
      text: WarrantyModels.readString(_from, 'category'),
    );
    _brand = TextEditingController(
      text: WarrantyModels.readString(_from, 'brand'),
    );
    _model = TextEditingController(
      text: WarrantyModels.readString(_from, 'model'),
    );
    _serial = TextEditingController(
      text: WarrantyModels.readString(_from, 'serial'),
    );
    _merchant = TextEditingController(
      text: WarrantyModels.readString(_from, 'merchant'),
    );
    final purchased = WarrantyModels.readDate(_from, 'purchasedAt');
    _purchaseDate = TextEditingController(
      text: purchased == null ? '' : WarrantyParse.dateText(purchased),
    );
    final months = widget.existing != null
        ? WarrantyModels.readCount(_from, 'durationMonths')
        : null;
    if (months != null) {
      _duration.text = '$months';
    } else if (widget.existing != null) {
      final end = WarrantyModels.readDate(_from, 'coverageEnd');
      if (end != null) _endDate.text = WarrantyParse.dateText(end);
    }
    _coverageType = TextEditingController(
      text: WarrantyModels.readString(_from, 'coverageType'),
    );
    _receiptRef = TextEditingController(
      text: WarrantyModels.readString(_from, 'receiptRef'),
    );
    _amount = TextEditingController();
    final rials = widget.existing != null
        ? WarrantyModels.readCount(_from, 'amountRials')
        : null;
    if (rials != null) {
      // Edit in the unit that needs no decimals: whole tomans when the
      // amount divides by ten, rials otherwise.
      _inTomans = rials % 10 == 0;
      _amount.text = _inTomans ? '${rials ~/ 10}' : '$rials';
    }
    _note = TextEditingController(
      text: WarrantyModels.readString(_from, 'note'),
    );
    for (final controller in _controllers) {
      controller.addListener(_onChanged);
    }
    _session = EditorCheckpoint(
      widget.store,
      'warranty',
      widget.existing,
      {
        'product': _product,
        'category': _category,
        'brand': _brand,
        'model': _model,
        'serial': _serial,
        'merchant': _merchant,
        'purchase': _purchaseDate,
        'duration': _duration,
        'end': _endDate,
        'coverageType': _coverageType,
        'receiptRef': _receiptRef,
        'amount': _amount,
        'note': _note,
      },
      () => {'inTomans': _inTomans},
      (saved) {
        if (saved['inTomans'] is bool) _inTomans = saved['inTomans'] as bool;
      },
      () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    unawaited(_session.load());
  }

  List<TextEditingController> get _controllers => [
    _product,
    _category,
    _brand,
    _model,
    _serial,
    _merchant,
    _purchaseDate,
    _duration,
    _endDate,
    _coverageType,
    _receiptRef,
    _amount,
    _note,
  ];

  @override
  void dispose() {
    _session.dispose();
    for (final controller in _controllers) {
      controller.removeListener(_onChanged);
      controller.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    setState(() => _dirty = true);
    _session.changed();
  }

  // -------------------------------------------------------------- parsing

  DateTime? get _purchase => WarrantyParse.date(_purchaseDate.text);

  /// The coverage end the form currently stands for, computed in front of
  /// the person when a duration is written — or null when the form does
  /// not yet hold one.
  DateTime? get _coverageEnd {
    final end = WarrantyParse.date(_endDate.text);
    if (end != null && end != WarrantyParse.invalid) {
      return end;
    }
    final months = WarrantyParse.count(_duration.text);
    final purchase = _purchase;
    if (months != null &&
        months > 0 &&
        months <= 2400 &&
        purchase != null &&
        purchase != WarrantyParse.invalid &&
        purchase.year + (purchase.month + months - 1) ~/ 12 <= 2100) {
      return WarrantyLogic.addMonths(
        DateTime(purchase.year, purchase.month, purchase.day),
        months,
      );
    }
    return null;
  }

  bool get _purchaseBad =>
      _purchase == null || _purchase == WarrantyParse.invalid;

  bool get _amountBad {
    final rials = WarrantyParse.rials(_amount.text, inTomans: _inTomans);
    return _amount.text.trim().isNotEmpty && rials == null;
  }

  // -------------------------------------------------------------- saving

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
      setState(() {
        _showErrors = true;
        if (_amountBad) _more = true;
      });
      return;
    }
    if (!WarrantyLogic.endAfterPurchase(purchase!, end)) {
      setState(() => _showErrors = true);
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
      'coverageType': ['coverageType'],
      'receiptRef': ['receiptRef'],
      'note': ['note'],
      'purchasedAt': ['purchase'],
      'coverageEnd': ['purchase', 'duration', 'end'],
      'durationMonths': ['duration', 'end'],
      'amountRials': ['amount', 'inTomans'],
    });
    setState(() => _session.busy = true);
    try {
      await WarrantyRepository.save(
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
    } catch (_) {
      _saveError();
    } finally {
      if (mounted) {
        setState(() => _session.busy = false);
      }
    }
  }

  // ------------------------------------------------------------ leaving

  Future<void> _maybePop() async {
    if (_session.busy) {
      return;
    }
    if (!_dirty) {
      setState(() => _session.busy = true);
      final kept = await _session.draft.finish();
      if (!mounted) return;
      if (kept) {
        Navigator.of(context).pop();
      } else {
        if (!_session.failed) _session.draft.resume();
        setState(() => _session.busy = false);
        _saveError();
      }
      return;
    }
    final leave = await WarrantyDialogs.confirmDiscard(
      context,
      warrantyStrings,
    );
    if (leave == true && mounted) {
      setState(() => _session.busy = true);
      if (await _session.discard() && mounted) {
        Navigator.of(context).pop();
      } else {
        if (!_session.failed) _session.draft.resume();
        setState(() => _session.busy = false);
        _saveError();
      }
    }
  }

  Future<void> _keepDraft() async {
    if (_session.busy || _session.loading || _session.failed) {
      return;
    }
    setState(() => _session.busy = true);
    final saved = await _session.draft.finish();
    if (!mounted) {
      return;
    }
    if (saved) {
      Navigator.of(context).pop();
    } else {
      _session.draft.resume();
      setState(() => _session.busy = false);
      _saveError();
    }
  }

  void _saveError() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(warrantyStrings(context, 'saveFailed'))),
    );
  }

  // -------------------------------------------------------------- build

  void _paint(VoidCallback change) {
    if (mounted) {
      setState(change);
    }
  }

  @override
  Widget build(BuildContext context) => _editorBody(context);
}
