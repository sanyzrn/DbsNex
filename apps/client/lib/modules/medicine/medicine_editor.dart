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
import 'medicine_sections.dart';
import 'medicine_strings.dart';
import 'medicine_widgets.dart';
import 'nex_text_field.dart';

part 'medicine_editor_body.dart';
part 'medicine_editor_details.dart';
part 'medicine_editor_actions.dart';

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
  late final TextEditingController _person;
  late final TextEditingController _every;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _warn;

  List<String> _times = const [];
  Set<int> _weekdays = {};
  bool _hardToFind = false;
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
        _person,
        _instructions,
        _time,
        _days,
        _purpose,
        _quantity,
        _doseUnits,
        _expiry,
        _refill,
        _every,
        _start,
        _end,
        _warn,
      ].any((c) => c.text.trim().isNotEmpty) ||
      _weekdays.isNotEmpty ||
      _hardToFind;

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
    _person = TextEditingController(text: MedicineModels.readPerson(_from));
    _every = TextEditingController(
      text: MedicineModels.readEveryDays(_from)?.toString() ?? '',
    );
    final startsOn = MedicineModels.readDay(_from, 'startsOn');
    _start = TextEditingController(
      text: startsOn == null ? '' : MedicineFields.dateText(startsOn),
    );
    final endsOn = MedicineModels.readDay(_from, 'endsOn');
    _end = TextEditingController(
      text: endsOn == null ? '' : MedicineFields.dateText(endsOn),
    );
    _warn = TextEditingController(
      text: MedicineModels.readCount(_from, 'warnDays')?.toString() ?? '',
    );
    _weekdays = MedicineModels.readWeekdays(_from).toSet();
    _hardToFind = MedicineModels.readHardToFind(_from);
    final quantity = MedicineModels.readCount(_from, 'quantity');
    if (quantity != null) _quantity.text = '$quantity';
    final doseUnits = MedicineModels.readCount(_from, 'doseUnits');
    if (doseUnits != null) _doseUnits.text = '$doseUnits';
    final expiresAt = MedicineModels.readDate(_from, 'expiresAt');
    if (expiresAt != null) {
      // Padded like the shared calendar button writes it, so a reopened
      // editor and a freshly picked day read the same.
      _expiry.text = MedicineFields.dateText(expiresAt);
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
        'person': _person,
        'every': _every,
        'start': _start,
        'end': _end,
        'warn': _warn,
      },
      () => {
        'times': _times,
        'weekdays': _weekdays.toList()..sort(),
        'hardToFind': _hardToFind,
      },
      (saved) {
        final times = saved['times'];
        if (times is List) _times = times.whereType<String>().toList();
        final weekdays = saved['weekdays'];
        if (weekdays is List) {
          _weekdays = weekdays.whereType<int>().toSet();
        }
        if (saved['hardToFind'] is bool) {
          _hardToFind = saved['hardToFind']! as bool;
        }
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
    _person,
    _every,
    _start,
    _end,
    _warn,
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

  // -------------------------------------------------------------- build

  void _paint(VoidCallback change) {
    if (mounted) {
      setState(change);
    }
  }

  @override
  Widget build(BuildContext context) => _editorBody(context);
}
