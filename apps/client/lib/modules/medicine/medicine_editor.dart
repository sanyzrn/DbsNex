import 'dart:async';
import 'editor_checkpoint.dart';
import 'medicine_repository.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_dialogs.dart';
import 'medicine_fields.dart';
import 'medicine_logic.dart';
import 'medicine_models.dart';
import 'medicine_parse.dart';
import 'medicine_strings.dart';
import 'medicine_widgets.dart';
import 'nex_text_field.dart';

part 'medicine_editor_body.dart';

/// What the editor hands back: a body ready to store, and the record it
/// belongs to when it is an edit of one that exists.
class MedicineDraft {
  const MedicineDraft({this.id, required this.body});

  final String? id;
  final Map<String, Object?> body;
}

/// The one form this module has: a medicine exactly as the person knows
/// it, in their own words. It does not suggest, complete or check anything
/// medical — the safety note under the form says who does.
///
/// Leaving with unsaved words asks first, so a pull at the sheet or the
/// back gesture cannot throw away what has been written.
class MedicineEditorSheet extends StatefulWidget {
  const MedicineEditorSheet({
    super.key,
    required this.store,
    this.existing,
    this.existingNames = const [],
  });

  final NexModuleStore store;
  final ModuleRecord? existing;

  /// The names already on the list, so a new entry can be asked about
  /// before the sheet closes and the draft is lost.
  final List<String> existingNames;

  @override
  State<MedicineEditorSheet> createState() => _MedicineEditorSheetState();
}

class _MedicineEditorSheetState extends State<MedicineEditorSheet> {
  late final Map<String, Object?> _from;
  late final TextEditingController _name;
  late final TextEditingController _strength;
  late final TextEditingController _packageUnit;
  late final TextEditingController _instructions;
  final _time = TextEditingController();
  late final TextEditingController _days;
  late final TextEditingController _purpose;
  final _quantity = TextEditingController();
  final _doseUnits = TextEditingController();
  final _expiry = TextEditingController();
  final _refill = TextEditingController();

  List<String> _times = const [];
  late final EditorCheckpoint _session;
  bool _dirty = false;
  bool _showErrors = false;
  // A new medicine asks its name, strength and package; everything else
  // waits behind one button — and opens by itself for a saved medicine, for a
  // draft that already has something in it, or when a save is refused there.
  bool _more = false;

  bool get _moreOpen =>
      _more ||
      widget.existing != null ||
      _times.isNotEmpty ||
      [
        _instructions,
        _time,
        _days,
        _purpose,
        _quantity,
        _doseUnits,
        _expiry,
        _refill,
      ].any((c) => c.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _from = widget.existing?.body ?? const {};
    _name = TextEditingController(
      text: MedicineModels.readString(_from, 'name'),
    );
    _strength = TextEditingController(
      text: MedicineModels.readString(_from, 'strength'),
    );
    _packageUnit = TextEditingController(
      text: MedicineModels.readString(_from, 'package'),
    );
    _instructions = TextEditingController(
      text: MedicineModels.readString(_from, 'instructions'),
    );
    _days = TextEditingController(
      text: MedicineModels.readString(_from, 'days'),
    );
    _purpose = TextEditingController(
      text: MedicineModels.readString(_from, 'purpose'),
    );
    final quantity = MedicineModels.readCount(_from, 'quantity');
    if (quantity != null) _quantity.text = '$quantity';
    final doseUnits = MedicineModels.readCount(_from, 'doseUnits');
    if (doseUnits != null) _doseUnits.text = '$doseUnits';
    final expiresAt = MedicineModels.readDate(_from, 'expiresAt');
    if (expiresAt != null) {
      // Padded like the shared calendar button writes it, so a reopened
      // editor and a freshly picked day read the same.
      _expiry.text =
          '${expiresAt.year}/${MedicineFields.two(expiresAt.month)}/'
          '${MedicineFields.two(expiresAt.day)}';
    }
    final refill = MedicineModels.readCount(_from, 'refillThreshold');
    if (refill != null) _refill.text = '$refill';
    _times = MedicineModels.readTimes(_from);
    for (final controller in _controllers) {
      controller.addListener(_onChanged);
    }
    _session = EditorCheckpoint(
      widget.store,
      'medicine',
      widget.existing,
      {
        'name': _name,
        'strength': _strength,
        'package': _packageUnit,
        'instructions': _instructions,
        'time': _time,
        'days': _days,
        'purpose': _purpose,
        'quantity': _quantity,
        'doseUnits': _doseUnits,
        'expiry': _expiry,
        'refill': _refill,
      },
      () => {'times': _times},
      (saved) {
        final times = saved['times'];
        if (times is List) _times = times.whereType<String>().toList();
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
    _name,
    _strength,
    _packageUnit,
    _instructions,
    _time,
    _days,
    _purpose,
    _quantity,
    _doseUnits,
    _expiry,
    _refill,
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
        expiry == MedicineParse.invalid) {
      setState(() {
        _showErrors = true;
        _more = true;
      });
      return;
    }
    if (_time.text.trim().isNotEmpty) _rememberTime(_time.text);
    setState(() => _session.busy = true);
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
        setState(() => _session.busy = false);
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
      setState(() {}); // Show the invalid-time helper.
      return;
    }
    setState(() {
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
    final leave = await MedicineDialogs.confirmDiscard(
      context,
      medicineStrings,
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
      SnackBar(content: Text(medicineStrings(context, 'saveFailed'))),
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
