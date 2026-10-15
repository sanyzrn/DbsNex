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
import 'smoke_math.dart';

/// The first-run setup — and the same sheet, prefilled, for correcting the
/// baseline later. Four honest numbers, no calendar tricks: "I quit N days
/// ago" (0 for today), cigarettes a day before quitting, the price of a
/// pack in integer rials, and how many cigarettes a pack holds.
Future<void> showSetupSheet(
  BuildContext context,
  NexModuleStore store, {
  QuitAttempt? editing,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (context) => _SetupSheet(store: store, editing: editing),
);

class _SetupSheet extends StatefulWidget {
  const _SetupSheet({required this.store, required this.editing});

  final NexModuleStore store;
  final QuitAttempt? editing;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  late final TextEditingController _daysAgo;
  late final TextEditingController _perDay;
  late final TextEditingController _price;
  late final TextEditingController _perPack;
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
    _perDay = TextEditingController(text: '${editing?.cigarettesPerDay ?? 20}');
    _price = TextEditingController(
      text: moneyInput(editing?.pricePerPackMinor ?? 0, _digits),
    );
    _perPack = TextEditingController(text: '${editing?.perPack ?? 20}');
    _draft = FormDraft(
      widget.store,
      'quit:${widget.editing?.id ?? 'new'}',
      widget.editing?.toJson() ?? const {},
      {
        'daysAgo': _daysAgo,
        'perDay': _perDay,
        'price': _price,
        'perPack': _perPack,
      },
      () => {
        'recordId': _recordId,
        'currency': _currency,
        'digits': _digits,
        'anchor': _anchor.toIso8601String(),
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

    setState(() {
      _daysError = days == null || days < 0
          ? days == null
                ? strings(context, 'numberInvalid')
                : strings(context, 'daysInvalid')
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
        _perPackError != null) {
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    final startedAt =
        widget.editing != null &&
            days == SmokeSetupMath.daysAgoOf(widget.editing!.startedAt, _anchor)
        ? widget.editing!.startedAt
        : DateTime(
            _anchor.year,
            _anchor.month,
            _anchor.day - days!,
            _anchor.hour,
            _anchor.minute,
            _anchor.second,
          );
    final body = <String, Object?>{
      'startedAt': startedAt.toIso8601String(),
      'cigarettesPerDay': perDay!.clamp(0, 1000),
      'v': 2,
      'pricePerPackMinor': price!,
      if (_currency == 'IRR') 'pricePerPackRials': price,
      'currency': _currency,
      'currencyDecimals': _digits,
      'perPack': perPack!.clamp(1, 100),
      // Editing never touches the attempt's end: an ended attempt stays
      // ended, a running one keeps running.
      'endedAt': widget.editing?.endedAt?.toIso8601String(),
      'endedWhy': widget.editing?.endedWhy,
    };
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
                  strings(context, _editing ? 'setupEditTitle' : 'setupTitle'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.sm),
                Text(
                  strings(context, 'explainBaseline'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                _NumberField(
                  key: const ValueKey('smoke-field-days'),
                  controller: _daysAgo,
                  label: strings(context, 'daysAgoLabel'),
                  hint: strings(context, 'daysAgoHint'),
                  errorText: _daysError,
                ),
                const SizedBox(height: NexSpacing.md),
                _NumberField(
                  key: const ValueKey('smoke-field-perday'),
                  controller: _perDay,
                  label: strings(context, 'perDayLabel'),
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
                  label: strings(context, 'priceLabel'),
                  errorText: _priceError,
                  hint: strings(context, 'amountHint', {
                    'example': localDigits(
                      moneyInput(12345, _digits),
                      NexModuleStrings.persian(context),
                    ),
                  }),
                ),
                const SizedBox(height: NexSpacing.md),
                _NumberField(
                  key: const ValueKey('smoke-field-perpack'),
                  controller: _perPack,
                  label: strings(context, 'perPackLabel'),
                  errorText: _perPackError,
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
