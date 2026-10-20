import 'dart:async';
import 'editor_checkpoint.dart';
import 'parking_repository.dart';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'nex_text_field.dart';
import 'parking_dialogs.dart';
import 'parking_fields.dart';
import 'parking_models.dart';
import 'parking_parse.dart';
import 'parking_strings.dart';
import 'parking_writes.dart';

part 'parking_editor_body.dart';

/// What the editor hands back: a body ready to store, and the record it
/// belongs to when it is an edit of one that exists.
class ParkingDraft {
  const ParkingDraft({this.id, required this.body});

  final String? id;
  final Map<String, Object?> body;
}

/// «Parked here» — the one form this module has. Everything in it is
/// typed by the person: the location is not found by the phone, and the
/// paid time is written by hand, not measured.
///
/// Leaving with unsaved words asks first, so a pull at the sheet's top or
/// the back gesture cannot throw away what has been written.
class ParkingEditorSheet extends StatefulWidget {
  const ParkingEditorSheet({
    super.key,
    required this.store,
    this.existing,
    this.place,
  });

  final NexModuleStore store;

  /// The record being edited, when there is one.
  final ModuleRecord? existing;

  /// A remembered place to prefill from, for a fresh parking.
  final Map<String, Object?>? place;

  @override
  State<ParkingEditorSheet> createState() => _ParkingEditorSheetState();
}

class _ParkingEditorSheetState extends State<ParkingEditorSheet> {
  late final Map<String, Object?> _from =
      widget.existing?.body ?? widget.place ?? const {};

  late final _vehicle = TextEditingController(
    text: widget.existing != null
        ? ParkingModels.readString(_from, 'vehicle')
        : '',
  );
  late final _place = TextEditingController(
    text: ParkingModels.readString(_from, 'place'),
  );
  late final _floor = TextEditingController(
    text: ParkingModels.readString(_from, 'floor'),
  );
  late final _spot = TextEditingController(
    text: ParkingModels.readString(_from, 'spot'),
  );
  late final _landmark = TextEditingController(
    text: ParkingModels.readString(_from, 'landmark'),
  );
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _expiryDate = TextEditingController();
  final _expiryTime = TextEditingController();

  late final EditorCheckpoint _session;
  bool _dirty = false;
  bool _showErrors = false;
  // A new parking asks where; the vehicle, floor and spot, landmark,
  // coordinates and the paid time wait behind one button — opened for a saved
  // parking, for a filled field, or by a refused save.
  bool _more = false;

  void _setMore(bool open) => setState(() => _more = open);

  bool get _moreOpen =>
      _more ||
      widget.existing != null ||
      [
        _vehicle,
        _floor,
        _spot,
        _landmark,
        _lat,
        _lng,
        _expiryDate,
        _expiryTime,
      ].any((c) => c.text.trim().isNotEmpty);
  DateTime _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    final lat = ParkingModels.readCoord(
      _from,
      'lat',
      min: ParkingModels.latMin,
      max: ParkingModels.latMax,
    );
    final lng = ParkingModels.readCoord(
      _from,
      'lng',
      min: ParkingModels.lngMin,
      max: ParkingModels.lngMax,
    );
    if (lat != null) _lat.text = ParkingParse.coordinateText(lat);
    if (lng != null) _lng.text = ParkingParse.coordinateText(lng);
    final expiresAt = widget.existing != null
        ? ParkingModels.readDate(_from, 'expiresAt')
        : null;
    if (expiresAt != null) {
      final (date, time) = ParkingParse.expiryText(expiresAt);
      _expiryDate.text = date;
      _expiryTime.text = time;
    }
    for (final controller in _controllers) {
      controller.addListener(_onChanged);
    }
    _session = EditorCheckpoint(
      widget.store,
      'session',
      widget.existing,
      {
        'vehicle': _vehicle,
        'place': _place,
        'floor': _floor,
        'spot': _spot,
        'landmark': _landmark,
        'lat': _lat,
        'lng': _lng,
        'expiryDate': _expiryDate,
        'expiryTime': _expiryTime,
      },
      () => {'startedAt': _startedAt.toUtc().toIso8601String()},
      (saved) {
        final started = ParkingModels.readDate(saved, 'startedAt');
        if (started != null) _startedAt = started;
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
    _vehicle,
    _place,
    _floor,
    _spot,
    _landmark,
    _lat,
    _lng,
    _expiryDate,
    _expiryTime,
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
    final expiry = ParkingParse.expiry(_expiryDate.text, _expiryTime.text);
    final lat = ParkingParse.coordinate(
      _lat.text,
      ParkingModels.latMin,
      ParkingModels.latMax,
    );
    final lng = ParkingParse.coordinate(
      _lng.text,
      ParkingModels.lngMin,
      ParkingModels.lngMax,
    );
    if (_place.text.trim().isEmpty ||
        expiry == ParkingParse.invalid ||
        (lat != null && lat.isNaN) ||
        (lng != null && lng.isNaN)) {
      setState(() {
        _showErrors = true;
        _more = true;
      });
      return;
    }

    final body = ParkingModels.sessionBody(
      vehicle: _vehicle.text,
      place: _place.text,
      floor: _floor.text,
      spot: _spot.text,
      landmark: _landmark.text,
      startedAt: ParkingModels.readDate(_from, 'startedAt') ?? _startedAt,
      foundAt: ParkingModels.readDate(_from, 'foundAt'),
      expiresAt: expiry,
      lat: lat,
      lng: lng,
    );
    final keys = _session.editedKeys(body, {
      'vehicle': ['vehicle'],
      'place': ['place'],
      'floor': ['floor'],
      'spot': ['spot'],
      'landmark': ['landmark'],
      'lat': ['lat'],
      'lng': ['lng'],
      'expiresAt': ['expiryDate', 'expiryTime'],
    });
    setState(() => _session.busy = true);
    try {
      try {
        await ParkingRepository.save(
          widget.store,
          _session.recordId,
          body,
          keys,
          existing: widget.existing != null,
        );
      } on ParkingConflict {
        if (!mounted) {
          return;
        }
        final close = await ParkingDialogs.askAboutEarlier(
          context,
          _vehicle.text,
          parkingStrings,
        );
        if (close != true || !mounted) {
          return;
        }
        await ParkingRepository.save(
          widget.store,
          _session.recordId,
          body,
          keys,
          existing: widget.existing != null,
          closeEarlier: true,
        );
      }
      await _session.draft.clear();
      // Remembered places are a convenience; the parking commit is authoritative.
      try {
        await ParkingWrites.rememberPlace(widget.store, const [], body);
      } catch (_) {}
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
    final leave = await ParkingDialogs.confirmDiscard(context, parkingStrings);
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
      SnackBar(content: Text(parkingStrings(context, 'saveFailed'))),
    );
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) => _editorBody(context);
}
