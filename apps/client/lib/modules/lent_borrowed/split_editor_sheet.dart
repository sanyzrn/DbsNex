import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_date_entry.dart';
import 'module.dart';
import 'split_cost_list.dart';
import 'split_cost_sheet.dart';
import 'split_discard.dart';
import 'loan_people.dart';
import 'split_math.dart';
import 'split_model.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

/// Starts a split, or changes one already saved: a name, the people who
/// share it, which of them is the person holding the phone, and the costs.
///
/// A saved split opens with everything it holds, so a wrong cost, a name or
/// a person is corrected in place — deleting the whole trip and retyping it
/// was the only way before.
Future<bool?> showSplitEditorSheet(
  BuildContext context,
  NexModuleStore store, {
  required IrrUnit unit,
  LoanSplit? existing,
}) => nexShowSheet<bool>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) =>
      SplitEditorSheet(store: store, unit: unit, existing: existing),
);

class SplitEditorSheet extends StatefulWidget {
  const SplitEditorSheet({
    super.key,
    required this.store,
    required this.unit,
    this.existing,
  });

  final NexModuleStore store;
  final IrrUnit unit;
  final LoanSplit? existing;

  @override
  State<SplitEditorSheet> createState() => _SplitEditorSheetState();
}

class _SplitEditorSheetState extends State<SplitEditorSheet> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _date = TextEditingController(
    text: dateEntryText(widget.existing?.date ?? splitToday()),
  );
  final _person = TextEditingController();
  late final List<String> _people = List.of(
    widget.existing?.people ?? const [],
  );
  late final List<SplitCost> _costs = List.of(
    widget.existing?.costs ?? const [],
  );
  late String _me = widget.existing?.me ?? '';
  String? _error;
  String? _personError;
  bool _saving = false;

  /// The form as it opened, so closing it untouched does not ask about a
  /// change nobody made.
  late final String _opened;

  @override
  void initState() {
    super.initState();
    if (_me.isEmpty && _people.isNotEmpty) _me = _people.first;
    _opened = _snapshot;
  }

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

  /// Removing someone who paid for a cost would leave that money without a
  /// payer; the cost is corrected first, and the message says so.
  void _removePerson(String person) {
    final pays = _costs.any(
      (cost) => personKey(cost.payer) == personKey(person),
    );
    if (pays) {
      setState(() {
        _personError = upgradeWord(context, 'splitPersonPays', {
          'person': person,
        });
      });
      return;
    }
    final needsCorrection = _costs.any(
      (cost) =>
          (cost.mode == SplitMode.amounts || cost.parts.length == 1) &&
          cost.parts.keys.any((name) => personKey(name) == personKey(person)),
    );
    if (needsCorrection) {
      setState(() {
        _personError = upgradeWord(context, 'splitPersonHasShare', {
          'person': person,
        });
      });
      return;
    }
    setState(() {
      _personError = null;
      _people.remove(person);
      if (personKey(_me) == personKey(person)) _me = '';
      for (var i = 0; i < _costs.length; i++) {
        final cost = _costs[i];
        if (cost.parts.keys.any((k) => personKey(k) == personKey(person))) {
          _costs[i] = cost.copyWith(
            parts: {
              for (final entry in cost.parts.entries)
                if (personKey(entry.key) != personKey(person))
                  entry.key: entry.value,
            },
          );
        }
      }
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

  Future<void> _editCost(int index) async {
    final cost = await showSplitCostSheet(
      context,
      people: _people,
      unit: widget.unit,
      existing: _costs[index],
    );
    if (cost != null && mounted) {
      setState(() {
        _costs[index] = cost;
        _personError = null;
      });
    }
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
    final existing = widget.existing;
    final split = LoanSplit(
      id: existing?.id ?? widget.store.newId(),
      title: _title.text.trim(),
      date: date!,
      me: _me,
      people: List.of(_people),
      costs: List.of(_costs),
    );
    final saved = await storeWrite(context, () async {
      // Fields a later version added are written back untouched.
      final old = existing == null
          ? null
          : await widget.store.get('split', existing.id);
      if (existing != null && old == null) {
        throw StateError('Split no longer exists');
      }
      await widget.store.put('split', split.id, split.toJson(previous: old));
    });
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).pop(true);
  }

  String get _snapshot => [
    _title.text.trim(),
    _date.text,
    _me,
    ..._people,
    for (final cost in _costs)
      '${cost.id}|${cost.title}|${cost.amount}|${cost.payer}'
          '|${cost.mode.name}|${cost.parts}',
  ].join('\u0000');

  bool get _dirty => _person.text.trim().isNotEmpty || _snapshot != _opened;

  Future<void> _cancel() async {
    if (_saving) return;
    if (_dirty && !await confirmSplitDiscard(context)) return;
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final editing = widget.existing != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancel());
      },
      child: SafeArea(
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
                strings(context, editing ? 'splitEdit' : 'splitNew'),
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
                              onDeleted: () => _removePerson(person),
                            ),
                        ],
                      ),
                      if (_personError case final error?) ...[
                        const SizedBox(height: NexSpacing.xs),
                        Text(
                          error,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: NexSpacing.sm),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('split-me'),
                        borderRadius: nexDropdownRadius,
                        dropdownColor: nexDropdownColor(context),
                        initialValue: _people.contains(_me) ? _me : null,
                        decoration: InputDecoration(
                          labelText: strings(context, 'splitMe'),
                        ),
                        items: [
                          for (final person in _people)
                            DropdownMenuItem(
                              value: person,
                              child: Text(person),
                            ),
                        ],
                        onChanged: (value) => setState(() => _me = value ?? ''),
                      ),
                    ],
                    const SizedBox(height: NexSpacing.md),
                    SplitCostList(
                      costs: _costs,
                      unit: widget.unit,
                      onAdd: () => unawaited(_addCost()),
                      onEdit: (index) => unawaited(_editCost(index)),
                      onRemove: (index) =>
                          setState(() => _costs.removeAt(index)),
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
                    onPressed: _saving ? null : () => unawaited(_cancel()),
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
      ),
    );
  }
}
