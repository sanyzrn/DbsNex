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
    habit: editing?.habit ?? habit,
    name: editing?.name ?? name,
    choose: choose && editing == null,
  ),
);

class _SetupSheet extends StatefulWidget {
  const _SetupSheet({
    required this.store,
    required this.editing,
    required this.habit,
    required this.name,
    required this.choose,
  });

  final NexModuleStore store;
  final QuitAttempt? editing;
  final String habit;
  final String name;
  final bool choose;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
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
    _currency = editing?.currency ?? 'IRR';
    _digits = editing?.digits ?? 0;
    final now = DateTime.now();
    _daysAgo = TextEditingController(
      text: editing == null
          ? '0'
          // Editing shows the current start as "days ago", so correcting it
          // is the same gesture as setting it.
          : '${SmokeSetupMath.daysAgoOf(editing.startedAt, now)}',
    );
    _perDay = TextEditingController(
      text: '${editing?.cigarettesPerDay ?? _preset.perDay}',
    );
    _price = TextEditingController(
      text: moneyInput(editing?.pricePerPackMinor ?? 0, _digits),
    );
    _perPack = TextEditingController(
      text: '${editing?.perPack ?? (_preset.packs ? 20 : 1)}',
    );
    _name = TextEditingController(text: widget.name);
    _minutes = TextEditingController(
      text: '${editing?.minutesPerUnit ?? _preset.minutesPerUnit}',
    );
    _goal = TextEditingController(
      text: (editing?.goalMinor ?? 0) == 0
          ? ''
          : moneyInput(editing!.goalMinor, _digits),
    );
    _why = TextEditingController(text: editing?.why ?? '');
    _draft = FormDraft(
      widget.store,
      'quit:${widget.editing?.id ?? 'new'}',
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
    setState(() => _restoring = false);
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

    final startedAt = _later
        // Begins at the start of that day: a plan, counted from then.
        ? DateTime(_anchor.year, _anchor.month, _anchor.day + days!)
        : widget.editing != null &&
              days ==
                  SmokeSetupMath.daysAgoOf(widget.editing!.startedAt, _anchor)
        ? widget.editing!.startedAt
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
      goalMinor: goal ?? 0,
      minutesPerUnit: minutes.clamp(0, 1440),
    );
    final body = <String, Object?>{...attempt.toJson()};
    final id = _recordId;
    final saved = await storeWrite(context, () async {
      await widget.store.put('quit', id, body);
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

  @override
  Widget build(BuildContext context) {
    if (!_restoring) _draft.changed();
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DraftGuard(
      draft: _draft,
      busy: () => _saving,
      child: AbsorbPointer(
        absorbing: _restoring || _saving,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: NexSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: NexSpacing.md),
                Text(
                  strings(
                    context,
                    _editing
                        ? 'setupEditTitle'
                        : widget.choose
                        ? 'chooseHabit'
                        : 'setupTitle',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.sm),
                if (widget.choose) ...[
                  Wrap(
                    spacing: NexSpacing.sm,
                    runSpacing: NexSpacing.xs,
                    children: [
                      for (final preset in quitPresets)
                        ChoiceChip(
                          key: ValueKey('quit-preset-${preset.key}'),
                          avatar: Icon(preset.icon, size: 18),
                          label: Text(strings(context, 'habit_${preset.key}')),
                          selected: _habit == preset.key,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() {
                                  _habit = preset.key;
                                  _perDay.text = '${preset.perDay}';
                                  _perPack.text = preset.packs ? '20' : '1';
                                  _minutes.text = '${preset.minutesPerUnit}';
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.md),
                ],
                if (_habit == 'custom') ...[
                  NexAutoDirection(
                    controller: _name,
                    builder: (context, direction) => TextField(
                      key: const ValueKey('quit-field-name'),
                      controller: _name,
                      textDirection: direction,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: strings(context, 'customName'),
                        hintText: strings(context, 'customNameHint'),
                        errorText: _nameError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                ],
                if (_preset.safety) ...[
                  NexPanel(
                    key: const ValueKey('quit-safety'),
                    icon: Icons.health_and_safety_outlined,
                    child: Text(
                      strings(context, 'safetyNote'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                ],
                if (_details) ...[
                  Text(
                    strings(context, 'explainBaseline'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                ],
                if (!_editing) ...[
                  SegmentedButton<bool>(
                    key: const ValueKey('quit-start-mode'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(strings(context, 'startedAlready')),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(strings(context, 'startsLater')),
                      ),
                    ],
                    selected: {_later},
                    onSelectionChanged: (s) => setState(() {
                      _later = s.first;
                      _daysAgo.text = _later ? '1' : '0';
                    }),
                  ),
                  const SizedBox(height: NexSpacing.md),
                ],
                _NumberField(
                  key: const ValueKey('smoke-field-days'),
                  controller: _daysAgo,
                  label: strings(
                    context,
                    _later ? 'startsInDaysLabel' : 'daysAgoLabel',
                  ),
                  hint: _later ? null : strings(context, 'daysAgoHint'),
                  errorText: _daysError,
                ),
                const SizedBox(height: NexSpacing.md),
                NexMoreDetails(
                  toggleKey: const ValueKey('quit-details-toggle'),
                  open: _details,
                  onChanged: (open) => setState(() => _details = open),
                  title: strings(context, 'addDetails'),
                  hint: strings(context, 'addDetailsHint'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _NumberField(
                        key: const ValueKey('smoke-field-perday'),
                        controller: _perDay,
                        label: _preset.packs
                            ? strings(context, 'perDayLabel')
                            : strings(context, 'perDayUnitsLabel', {
                                'unit': _unit(context),
                              }),
                        errorText: _perDayError,
                      ),
                      const SizedBox(height: NexSpacing.md),
                      CurrencyField(
                        key: const ValueKey('smoke-field-currency'),
                        value: _currency,
                        onChanged: _saving
                            ? null
                            : (code) => setState(() {
                                _currency = code;
                                _digits = moneyDigits(code);
                                _price.clear();
                              }),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      _NumberField(
                        decimal: _digits > 0,
                        suffix: _currency,
                        key: const ValueKey('smoke-field-price'),
                        controller: _price,
                        label: strings(
                          context,
                          _preset.packs ? 'priceLabel' : 'unitPriceLabel',
                        ),
                        errorText: _priceError,
                        hint: strings(context, 'amountHint', {
                          'example': localDigits(
                            moneyInput(12345, _digits),
                            NexModuleStrings.persian(context),
                          ),
                        }),
                      ),
                      if (_preset.packs) ...[
                        const SizedBox(height: NexSpacing.md),
                        _NumberField(
                          key: const ValueKey('smoke-field-perpack'),
                          controller: _perPack,
                          label: strings(context, 'perPackLabel'),
                          errorText: _perPackError,
                        ),
                      ],
                      const SizedBox(height: NexSpacing.md),
                      _NumberField(
                        key: const ValueKey('quit-field-minutes'),
                        controller: _minutes,
                        label: strings(context, 'minutesLabel'),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      _NumberField(
                        key: const ValueKey('quit-field-goal'),
                        decimal: _digits > 0,
                        suffix: _currency,
                        controller: _goal,
                        label: strings(context, 'goalLabel'),
                        errorText: _goalError,
                      ),
                      const SizedBox(height: NexSpacing.md),
                      NexTextField(
                        key: const ValueKey('quit-field-why'),
                        controller: _why,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: strings(context, 'whyLabel'),
                          hintText: strings(context, 'whyHint'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NexSpacing.lg),
                FilledButton(
                  key: const ValueKey('smoke-save'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _saving ? null : () => _save(),
                  child: _saving
                      ? const NexInlineSpinner(size: 20)
                      : Text(
                          strings(
                            context,
                            _editing ? 'setupEditTitle' : 'startAttempt',
                          ),
                        ),
                ),
                const SizedBox(height: NexSpacing.sm),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          await _draft.clear();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  child: Text(l10n.cancel),
                ),
                const SizedBox(height: NexSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A whole-number field: left-to-right digits, no symbols, a plain
/// keyboard. The number a person writes here is an amount or a count —
/// never prose.
class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.errorText,
    this.decimal = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? errorText;
  final bool decimal;
  final String? suffix;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    textDirection: TextDirection.ltr,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      suffixText: suffix,
      border: const OutlineInputBorder(),
    ),
  );
}

/// The start date expressed as "N days ago" — the sheet's honest way of
/// asking when quitting happened without drawing a calendar the platform
/// cannot honestly draw.
abstract final class SmokeSetupMath {
  static int daysAgoOf(DateTime startedAt, DateTime now) =>
      SmokeMath.elapsedDays(startedAt, now);
}
