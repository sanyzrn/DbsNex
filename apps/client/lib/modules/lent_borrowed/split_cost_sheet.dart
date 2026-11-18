import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'amount_field.dart';
import 'irr_unit.dart';
import 'loan_fields.dart';
import 'module.dart';
import 'money_format.dart';
import 'split_model.dart';
import 'upgrade_strings.dart';

/// Add or change one cost inside a split: what it was, how much, who paid,
/// and how the people sharing it divide it.
Future<SplitCost?> showSplitCostSheet(
  BuildContext context, {
  required List<String> people,
  required IrrUnit unit,
  SplitCost? existing,
}) => nexShowSheet<SplitCost>(
  context: context,
  builder: (_) =>
      SplitCostSheet(people: people, unit: unit, existing: existing),
);

class SplitCostSheet extends StatefulWidget {
  const SplitCostSheet({
    super.key,
    required this.people,
    required this.unit,
    this.existing,
  });

  final List<String> people;
  final IrrUnit unit;
  final SplitCost? existing;

  @override
  State<SplitCostSheet> createState() => _SplitCostSheetState();
}

class _SplitCostSheetState extends State<SplitCostSheet> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : amountInput(widget.existing!.amount, 'IRR', 0, widget.unit),
  );
  late String _payer = widget.people.contains(widget.existing?.payer)
      ? widget.existing!.payer
      : widget.people.first;
  late SplitMode _mode = widget.existing?.mode ?? SplitMode.equal;
  final _fields = <String, TextEditingController>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final person in widget.people) {
      final part = widget.existing?.parts[person];
      _fields[person] = TextEditingController(
        text: part == null
            ? (_mode == SplitMode.shares ? '1' : '')
            : _mode == SplitMode.amounts
            ? amountInput(part, 'IRR', 0, widget.unit)
            : '$part',
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  int? get _amountRials => parseAmount(_amount.text, 'IRR', 0, widget.unit);

  Map<String, int>? _parts() {
    final amount = _amountRials;
    if (amount == null || amount <= 0) return null;
    switch (_mode) {
      case SplitMode.equal:
        return {for (final person in widget.people) person: 0};
      case SplitMode.shares:
        final parts = <String, int>{};
        for (final person in widget.people) {
          final value = int.tryParse(cardDigitsFor(_fields[person]!.text));
          if (value == null || value < 1) return null;
          parts[person] = value;
        }
        return parts;
      case SplitMode.amounts:
        final parts = <String, int>{};
        var sum = 0;
        for (final person in widget.people) {
          final value = parseAmount(
            _fields[person]!.text,
            'IRR',
            0,
            widget.unit,
          );
          if (value == null || value < 0) return null;
          parts[person] = value;
          sum += value;
        }
        return sum == amount ? parts : null;
    }
  }

  void _save() {
    final amount = _amountRials;
    final parts = _parts();
    final message = amount == null || amount <= 0
        ? lentStrings(context, 'zeroAmount')
        : parts == null && _mode == SplitMode.amounts
        ? upgradeWord(context, 'splitCostBad')
        : parts == null
        ? upgradeWord(context, 'splitShareBad')
        : null;
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    Navigator.of(context).pop(
      SplitCost(
        id: widget.existing?.id ?? newSplitCostId(),
        title: _title.text.trim(),
        amount: amount!,
        payer: _payer,
        mode: _mode,
        parts: parts!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          NexSpacing.md,
          NexSpacing.sm,
          NexSpacing.md,
          NexSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings(context, 'splitAddCost'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.md),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  NexAutoDirection(
                    controller: _title,
                    builder: (context, _) => TextField(
                      key: const ValueKey('split-cost-name'),
                      controller: _title,
                      decoration: InputDecoration(
                        labelText: strings(context, 'splitCostName'),
                        hintText: strings(context, 'splitCostNameHint'),
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  AmountField(
                    fieldKey: const ValueKey('split-cost-amount'),
                    controller: _amount,
                    currency: 'IRR',
                    digits: 0,
                    unit: widget.unit,
                    label: strings(context, 'splitAmount'),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('split-cost-payer'),
                    initialValue: _payer,
                    decoration: InputDecoration(
                      labelText: strings(context, 'splitPaidBy'),
                    ),
                    items: [
                      for (final person in widget.people)
                        DropdownMenuItem(value: person, child: Text(person)),
                    ],
                    onChanged: (value) =>
                        setState(() => _payer = value ?? _payer),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Text(
                    strings(context, 'splitDivide'),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  NexAdaptiveSegments<SplitMode>(
                    key: const ValueKey('split-cost-mode'),
                    segments: [
                      ButtonSegment(
                        value: SplitMode.equal,
                        label: Text(strings(context, 'splitEqual')),
                      ),
                      ButtonSegment(
                        value: SplitMode.shares,
                        label: Text(strings(context, 'splitShares')),
                      ),
                      ButtonSegment(
                        value: SplitMode.amounts,
                        label: Text(strings(context, 'splitAmounts')),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (value) =>
                        setState(() => _mode = value.first),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  if (_mode == SplitMode.shares)
                    Text(
                      strings(context, 'splitSharesHint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (_mode != SplitMode.equal)
                    for (final person in widget.people) ...[
                      const SizedBox(height: NexSpacing.sm),
                      if (_mode == SplitMode.shares)
                        LoanNumberField(
                          fieldKey: ValueKey('split-share-$person'),
                          controller: _fields[person]!,
                          label: person,
                        )
                      else
                        AmountField(
                          fieldKey: ValueKey('split-part-$person'),
                          controller: _fields[person]!,
                          currency: 'IRR',
                          digits: 0,
                          unit: widget.unit,
                          label: person,
                        ),
                    ],
                  if (_error != null) ...[
                    const SizedBox(height: NexSpacing.sm),
                    Text(
                      _error!,
                      key: const ValueKey('split-cost-error'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('split-cost-save'),
                  onPressed: _save,
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Digits from any script, for the small share fields.
String cardDigitsFor(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + rune - 0x06F0);
    } else if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x30 && rune <= 0x39) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
