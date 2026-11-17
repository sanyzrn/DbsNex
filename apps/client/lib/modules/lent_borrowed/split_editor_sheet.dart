import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_date_entry.dart';
import 'module.dart';
import 'money_format.dart';
import 'split_cost_sheet.dart';
import 'loan_people.dart';
import 'split_math.dart';
import 'split_model.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

/// Starts a split: a name, the people who share it, which of them is the
/// person holding the phone, and the costs.
Future<bool?> showSplitEditorSheet(
  BuildContext context,
  NexModuleStore store, {
  required IrrUnit unit,
}) => nexShowSheet<bool>(
  context: context,
  builder: (_) => SplitEditorSheet(store: store, unit: unit),
);

class SplitEditorSheet extends StatefulWidget {
  const SplitEditorSheet({super.key, required this.store, required this.unit});

  final NexModuleStore store;
  final IrrUnit unit;

  @override
  State<SplitEditorSheet> createState() => _SplitEditorSheetState();
}

class _SplitEditorSheetState extends State<SplitEditorSheet> {
  final _title = TextEditingController();
  late final _date = TextEditingController(text: dateEntryText(splitToday()));
  final _person = TextEditingController();
  final _people = <String>[];
  final _costs = <SplitCost>[];
  String _me = '';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _date.dispose();
    _person.dispose();
    super.dispose();
  }

  void _addPerson() {
    final name = _person.text.trim();
    if (name.isEmpty) return;
    if (_people.any((p) => personKey(p) == personKey(name))) {
      _person.clear();
      return;
    }
    setState(() {
      _people.add(name);
      if (_me.isEmpty) _me = name;
      _person.clear();
    });
  }

  Future<void> _addCost() async {
    if (_people.length < 2) {
      setState(() => _error = upgradeWord(context, 'splitNoPeople'));
      return;
    }
    final cost = await showSplitCostSheet(
      context,
      people: _people,
      unit: widget.unit,
      existing: null,
    );
    if (cost != null && mounted) setState(() => _costs.add(cost));
  }

  Future<void> _save() async {
    if (_saving) return;
    final date = parseDateEntry(_date.text);
    final message = _title.text.trim().isEmpty
        ? upgradeWord(context, 'splitNoName')
        : _people.length < 2
        ? upgradeWord(context, 'splitNoPeople')
        : _costs.isEmpty
        ? upgradeWord(context, 'splitNoCostsSave')
        : date == null
        ? lentStrings(context, 'dateInvalid')
        : null;
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final split = LoanSplit(
      id: widget.store.newId(),
      title: _title.text.trim(),
      date: date!,
      me: _me,
      people: List.of(_people),
      costs: List.of(_costs),
    );
    final saved = await storeWrite(
      context,
      () => widget.store.put('split', split.id, split.toJson()),
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final persian = NexModuleStrings.persian(context);
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
              strings(context, 'splitNew'),
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
                      key: const ValueKey('split-field-title'),
                      controller: _title,
                      decoration: InputDecoration(
                        labelText: strings(context, 'splitName'),
                        hintText: strings(context, 'splitNameHint'),
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  NexModuleDateEntry(
                    controller: _date,
                    child: TextField(
                      key: const ValueKey('split-field-date'),
                      controller: _date,
                      keyboardType: TextInputType.datetime,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: strings(context, 'splitDate'),
                        hintText: lentStrings(context, 'dateHint'),
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Text(
                    strings(context, 'splitPeople'),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: NexAutoDirection(
                          controller: _person,
                          builder: (context, _) => TextField(
                            key: const ValueKey('split-field-person'),
                            controller: _person,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addPerson(),
                            decoration: InputDecoration(
                              hintText: strings(context, 'splitPersonHint'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: NexSpacing.sm),
                      IconButton.filledTonal(
                        key: const ValueKey('split-add-person'),
                        tooltip: strings(context, 'splitAddPerson'),
                        onPressed: _addPerson,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  if (_people.isNotEmpty) ...[
                    const SizedBox(height: NexSpacing.sm),
                    Wrap(
                      spacing: NexSpacing.sm,
                      runSpacing: NexSpacing.xs,
                      children: [
                        for (final person in _people)
                          InputChip(
                            key: ValueKey('split-person-$person'),
                            label: Text(person),
                            onDeleted: () => setState(() {
                              _people.remove(person);
                              if (_me == person) _me = '';
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('split-me'),
                      initialValue: _me.isEmpty ? null : _me,
                      decoration: InputDecoration(
                        labelText: strings(context, 'splitMe'),
                      ),
                      items: [
                        for (final person in _people)
                          DropdownMenuItem(value: person, child: Text(person)),
                      ],
                      onChanged: (value) => setState(() => _me = value ?? ''),
                    ),
                  ],
                  const SizedBox(height: NexSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings(context, 'splitCosts'),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('split-add-cost'),
                        onPressed: () => unawaited(_addCost()),
                        icon: const Icon(Icons.add),
                        label: Text(strings(context, 'splitAddCost')),
                      ),
                    ],
                  ),
                  if (_costs.isEmpty)
                    Text(
                      strings(context, 'splitNoCosts'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final (index, cost) in _costs.indexed)
                      ListTile(
                        key: ValueKey('split-cost-$index'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          cost.title.isEmpty
                              ? strings(context, 'splitAddCost')
                              : cost.title,
                        ),
                        subtitle: Text(
                          '${cost.payer} · ${formatAmount(cost.amount, 'IRR', 0, persian, widget.unit)}',
                        ),
                        trailing: IconButton(
                          key: ValueKey('split-cost-remove-$index'),
                          tooltip: strings(context, 'splitDelete'),
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _costs.removeAt(index)),
                        ),
                      ),
                  if (_error != null) ...[
                    const SizedBox(height: NexSpacing.sm),
                    Text(
                      _error!,
                      key: const ValueKey('split-error'),
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
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cancel),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('split-save'),
                  onPressed: _saving ? null : () => unawaited(_save()),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
