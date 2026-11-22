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
import 'warranty_reminder_offer.dart';
import 'warranty_strings.dart';

part 'warranty_editor_body.dart';
part 'warranty_editor_save.dart';

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
  late final TextEditingController _company;
  late final TextEditingController _supportPhone;
  late final TextEditingController _cardNumber;
  late final TextEditingController _receiptRef;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  /// Which of the three kinds of cover this is; '' when the person has not
  /// said. The difference matters: a company warranty, the shop's guarantee
  /// and after-sales service are not the same promise.
  String _coverKind = '';

  /// Who the device is registered to; '' when not written down.
  String _registry = '';

  /// Whether the amount is typed in tomans (true) or rials (false).
  bool _inTomans = false;

  /// The reminder offered as the purchase is saved: null until the person
  /// touches it, so a new purchase reminds by default and a saved one
  /// leaves an existing reminder alone.
  bool? _remind;
  int? _remindDays;

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
        _company,
        _supportPhone,
        _cardNumber,
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
    _coverageType = TextEditingController(
      text: WarrantyModels.readString(_from, 'coverageType'),
    );
    _company = TextEditingController(
      text: WarrantyModels.readString(_from, 'company'),
    );
    _supportPhone = TextEditingController(
      text: WarrantyModels.readString(_from, 'supportPhone'),
    );
    _cardNumber = TextEditingController(
      text: WarrantyModels.readString(_from, 'cardNumber'),
    );
    _coverKind = WarrantyModels.readCoverKind(_from);
    _registry = WarrantyModels.readRegistry(_from);
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
    _receiptRef = TextEditingController(
      text: WarrantyModels.readString(_from, 'receiptRef'),
    );
    _amount = NexMoneyController();
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
        'company': _company,
        'supportPhone': _supportPhone,
        'cardNumber': _cardNumber,
        'purchase': _purchaseDate,
        'duration': _duration,
        'end': _endDate,
        'coverageType': _coverageType,
        'receiptRef': _receiptRef,
        'amount': _amount,
        'note': _note,
      },
      () => {
        'inTomans': _inTomans,
        'coverKind': _coverKind,
        'registry': _registry,
        'remind': _remind,
        'remindDays': _remindDays,
      },
      (saved) {
        if (saved['inTomans'] is bool) _inTomans = saved['inTomans'] as bool;
        final coverKind = saved['coverKind'];
        if (coverKind is String) _coverKind = coverKind;
        final registry = saved['registry'];
        if (registry is String) _registry = registry;
        final remind = saved['remind'];
        if (remind is bool) _remind = remind;
        final days = saved['remindDays'];
        if (days is int) _remindDays = days;
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
    _company,
    _supportPhone,
    _cardNumber,
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

  // ------------------------------------------------------------ reminder

  /// Whether the reminder is offered at all: an end date far enough ahead
  /// that at least one of its lead times is still in the future.
  List<int> get _reminderChoices {
    final end = _coverageEnd;
    if (end == null) return const [];
    return WarrantyLogic.reminderChoices(end, DateTime.now());
  }

  /// The moment the offered reminder will ring, or null when there is
  /// nothing left to offer (the cover ends today or has already ended).
  DateTime? get _reminderMoment {
    final end = _coverageEnd;
    final choices = _reminderChoices;
    if (end == null || choices.isEmpty) return null;
    final days = choices.contains(_remindDays) ? _remindDays! : choices.first;
    return WarrantyLogic.reminderAt(end, days);
  }

  /// A new purchase reminds by default — "nothing expires unnoticed" is why
  /// the module exists — and a saved one leaves the person's existing
  /// reminder alone unless they ask for a new one.
  bool get _remindOn => _remind ?? (widget.existing == null);

  /// Whether the reminder can be offered at all: there is a future moment
  /// to set, and the platform will let this module schedule one.
  bool get _offerReminder =>
      widget.store.remindersEnabled && _reminderMoment != null;

  // -------------------------------------------------------------- build

  void _paint(VoidCallback change) {
    if (mounted) {
      setState(change);
    }
  }

  @override
  Widget build(BuildContext context) => _editorBody(context);
}
