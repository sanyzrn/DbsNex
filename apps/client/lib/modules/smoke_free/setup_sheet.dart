import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'store_state.dart';
import 'form_draft.dart';
import 'draft_guard.dart';
import 'quit_model.dart';
import 'currency_field.dart';
import 'money_format.dart';
import 'number_input.dart';
import 'quit_habits.dart';
import 'smoke_math.dart';
part 'setup_view.dart';

/// The first-run setup — and the same sheet, prefilled, for correcting the
/// baseline later. Four honest numbers, no calendar tricks: "I quit N days
/// ago" (0 for today), cigarettes a day before quitting, the price of a
/// pack in integer rials, and how many cigarettes a pack holds.
///
/// With [choose] the sheet opens on what is being quit — the presets and a
/// name for a custom one — which is how a new habit is added; without it the
/// habit is [habit] (cigarettes, the original) or the one being edited.
Future<void> showSetupSheet(
  BuildContext context,
  NexModuleStore store, {
  QuitAttempt? editing,
  QuitAttempt? resumeFrom,
  String habit = defaultHabit,
  String name = '',
  bool choose = false,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (context) => _SetupSheet(
    store: store,
    editing: editing,
    resumeFrom: resumeFrom,
    habit: editing?.habit ?? habit,
    name: editing?.name ?? name,
    choose: choose && editing == null,
  ),
);

class _SetupSheet extends StatefulWidget {
  const _SetupSheet({
    required this.store,
    required this.editing,
    required this.resumeFrom,
    required this.habit,
    required this.name,
    required this.choose,
  });

  final NexModuleStore store;
  final QuitAttempt? editing;
  final QuitAttempt? resumeFrom;
  final String habit;
  final String name;
  final bool choose;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

abstract class _SetupLogic extends State<_SetupSheet> {
  late final TextEditingController _daysAgo;
  late final TextEditingController _perDay;
  late final TextEditingController _price;
  late final TextEditingController _perPack;
  late final TextEditingController _name;
  late final TextEditingController _minutes;
  late final TextEditingController _goal;
  late final TextEditingController _why;
  late String _habit = widget.habit;
  bool _later = false;
  // A new habit asks only what it is and when it starts; the rest — the
  // amounts, the price, a goal, a reason — waits behind one button, so the
  // first minute is not a form. Correcting one opens everything.
  late bool _details = widget.editing != null;
  String? _nameError;
  String? _goalError;
  bool _saving = false;
  late final FormDraft _draft;
  bool _restoring = true;
  bool _loadFailed = false;
  late String _currency;
  late int _digits;
  late DateTime _anchor = DateTime.now();
  late final String _recordId = widget.editing?.id ?? widget.store.newId();
  String? _daysError;
  String? _perDayError;
  String? _priceError;
  String? _perPackError;

  bool get _editing => widget.editing != null;
  QuitPreset get _preset => quitPresetOf(_habit);

  String _unit(BuildContext context) =>
      smokeFreeStrings(context, 'unit_${_preset.key}');

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final baseline = editing ?? widget.resumeFrom;
    _currency = baseline?.currency ?? 'IRR';
    _digits = baseline?.digits ?? 0;
    final now = DateTime.now();
    _later = editing?.startedAt.isAfter(now) == true;
    _daysAgo = TextEditingController(
      text: editing == null
          ? '0'
          // Editing shows the current start as "days ago", so correcting it
          // is the same gesture as setting it.
          : '${_later ? SmokeMath.elapsedDays(now, editing.startedAt) : SmokeSetupMath.daysAgoOf(editing.startedAt, now)}',
    );
    _perDay = TextEditingController(
      text: '${baseline?.cigarettesPerDay ?? _preset.perDay}',
    );
    _price = TextEditingController(
      text: moneyInput(baseline?.pricePerPackMinor ?? 0, _digits),
    );
    _perPack = TextEditingController(
      text: '${baseline?.perPack ?? (_preset.packs ? 20 : 1)}',
    );
    _name = TextEditingController(text: widget.name);
    _minutes = TextEditingController(
      text: '${baseline?.minutesPerUnit ?? _preset.minutesPerUnit}',
    );
    _goal = TextEditingController(
      text: (baseline?.goalMinor ?? 0) == 0
          ? ''
          : moneyInput(baseline!.goalMinor, _digits),
    );
    _why = TextEditingController(text: baseline?.why ?? '');
    _draft = FormDraft(
      widget.store,
      widget.editing != null
          ? 'quit:${widget.editing!.id}'
          : widget.choose || widget.habit == defaultHabit
          ? 'quit:new'
          : 'quit:${widget.resumeFrom?.key ?? quitHabitKey(widget.habit, widget.name)}:new',
      widget.editing?.toJson() ?? const {},
      {
        'daysAgo': _daysAgo,
        'perDay': _perDay,
        'price': _price,
        'perPack': _perPack,
        'name': _name,
        'minutes': _minutes,
        'goal': _goal,
        'why': _why,
      },
      () => {
        'recordId': _recordId,
        'currency': _currency,
        'digits': _digits,
        'anchor': _anchor.toIso8601String(),
        'habit': _habit,
        'later': _later,
        'details': _details,
      },
    );
    unawaited(_restoreDraft());
  }

  Future<void> _restoreDraft() async {
    final body = await _draft.load();
    if (!mounted) return;
    if (_draft.loadFailed) {
      setState(() {
        _restoring = false;
        _loadFailed = true;
      });
      return;
    }
    if (body != null) {
      _draft.apply(body);
      _currency = currencyCode(body['currency']);
      _digits = moneyDigits(_currency, body['digits']);
      _anchor = DateTime.tryParse('${body['anchor'] ?? ''}') ?? _anchor;
      if (widget.choose && body['habit'] is String) {
        _habit = body['habit'] as String;
      }
      _later = body['later'] == true;
      // A draft that was already past the first questions comes back open.
      _details = _details || body['details'] == true;
    }
    _draft.start();
    setState(() {
      _restoring = false;
      _loadFailed = false;
    });
  }

  @override
  void dispose() {
    _draft.close();
    _daysAgo.dispose();
    _perDay.dispose();
    _price.dispose();
    _perPack.dispose();
    _name.dispose();
    _minutes.dispose();
    _goal.dispose();
    _why.dispose();
    super.dispose();
  }

  int? _parse(TextEditingController controller) =>
      parseWhole(controller.text, signed: true);

  Future<void> _save() async {
    final strings = smokeFreeStrings;
    final days = _parse(_daysAgo);
    final perDay = _parse(_perDay);
    final price = parseMoney(_price.text, _digits);
    final perPack = _parse(_perPack);

    final minutes = _parse(_minutes) ?? 0;
    final goalText = _goal.text.trim();
    final goal = goalText.isEmpty ? 0 : parseMoney(goalText, _digits);
    final customName = _name.text.trim();
    setState(() {
      _nameError = _habit == 'custom' && customName.isEmpty
          ? strings(context, 'nameRequired')
          : null;
      _goalError = goal == null || goal < 0
          ? strings(context, 'goalInvalid')
          : null;
      _daysError = days == null || days < 0 || (_later && days < 1)
          ? days == null
                ? strings(context, 'numberInvalid')
                : strings(
                    context,
                    _later ? 'daysFromNowInvalid' : 'daysInvalid',
                  )
          : null;
      _perDayError = perDay == null || perDay < 0 || perDay > 1000
          ? strings(context, 'numberInvalid')
          : null;
      _priceError = price == null || price < 0
          ? strings(context, 'priceInvalid')
          : null;
      _perPackError = perPack == null || perPack < 1 || perPack > 100
          ? strings(context, 'numberInvalid')
          : null;
    });
    if (_daysError != null ||
        _perDayError != null ||
        _priceError != null ||
        _perPackError != null ||
        _nameError != null ||
        _goalError != null) {
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    final unchangedDay =
        widget.editing != null &&
        _later == widget.editing!.startedAt.isAfter(_anchor) &&
        days ==
            (_later
                ? SmokeMath.elapsedDays(_anchor, widget.editing!.startedAt)
                : SmokeSetupMath.daysAgoOf(widget.editing!.startedAt, _anchor));
    final startedAt = unchangedDay
        ? widget.editing!.startedAt
        : _later
        // Begins at the start of that day: a plan, counted from then.
        ? DateTime(_anchor.year, _anchor.month, _anchor.day + days!)
        : DateTime(
            _anchor.year,
            _anchor.month,
            _anchor.day - days!,
            _anchor.hour,
            _anchor.minute,
            _anchor.second,
          );
    // Editing never touches the attempt's end: an ended attempt stays
    // ended, a running one keeps running.
    final attempt = QuitAttempt(
      id: _recordId,
      startedAt: startedAt,
      cigarettesPerDay: perDay!.clamp(0, 1000),
      pricePerPackMinor: price!,
      currency: _currency,
      currencyDecimals: _digits,
      perPack: perPack!.clamp(1, 100),
      endedAt: widget.editing?.endedAt,
      endedWhy: widget.editing?.endedWhy,
      habit: _habit,
      name: _habit == 'custom' ? customName : '',
      why: _why.text.trim(),
      nextStep: (widget.editing ?? widget.resumeFrom)?.nextStep ?? '',
      habitKey: _habit == 'custom'
          ? (widget.editing ?? widget.resumeFrom)?.key
          : null,
      goalMinor: goal ?? 0,
      minutesPerUnit: minutes.clamp(0, 1440),
    );
    final body = <String, Object?>{...attempt.toJson()};
    final id = _recordId;
    final saved = await storeWrite(context, () async {
      final prior = widget.editing == null
          ? null
          : await widget.store.get('quit', id);
      final merged = {...?prior}
        ..remove('why')
        ..remove('goalMinor')
        ..remove('minutesPerUnit');
      await widget.store.put('quit', id, {...merged, ...body});
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

/// The start date expressed as "N days ago" — the sheet's honest way of
/// asking when quitting happened without drawing a calendar the platform
/// cannot honestly draw.
abstract final class SmokeSetupMath {
  static int daysAgoOf(DateTime startedAt, DateTime now) =>
      SmokeMath.elapsedDays(startedAt, now);
}
