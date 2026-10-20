import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_model.dart';
import 'module.dart';
import 'adaptive_segments.dart';
import 'store_state.dart';
import 'form_draft.dart';
import 'draft_guard.dart';

/// Creates a habit, or edits one without touching its history: the sheet
/// writes the same record with the new name, note and schedule, and every
/// check-in keeps pointing at it.
Future<void> showHabitEditSheet(
  BuildContext context,
  NexModuleStore store, {
  Habit? habit,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (context) => _HabitEditSheet(store: store, habit: habit),
);

class _HabitEditSheet extends StatefulWidget {
  const _HabitEditSheet({required this.store, required this.habit});

  final NexModuleStore store;
  final Habit? habit;

  @override
  State<_HabitEditSheet> createState() => _HabitEditSheetState();
}

class _HabitEditSheetState extends State<_HabitEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late bool _weekly;
  late int _target;
  bool _saving = false;
  late final FormDraft _draft;
  bool _restoring = true;
  late final String _recordId = widget.habit?.id ?? widget.store.newId();
  String? _nameError;

  bool get _editing => widget.habit != null;

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    _name = TextEditingController(text: habit?.name ?? '');
    _note = TextEditingController(text: habit?.note ?? '');
    _weekly = habit?.weekly ?? false;
    _target = habit?.weekly == true ? (habit!.target) : 3;
    _draft = FormDraft(
      widget.store,
      'habit:${widget.habit?.id ?? 'new'}',
      widget.habit?.toJson() ?? const {},
      {'name': _name, 'note': _note},
      () => {'recordId': _recordId, 'weekly': _weekly, 'target': _target},
    );
    unawaited(_restoreDraft());
  }

  Future<void> _restoreDraft() async {
    final body = await _draft.load();
    if (!mounted) return;
    if (body != null) {
      _draft.apply(body);
      _weekly = body['weekly'] == true;
      final target = body['target'];
      if (target is int) _target = target.clamp(1, 7);
    }
    _draft.start();
    setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _draft.close();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = habitsStrings(context, 'nameRequired'));
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    final now = DateTime.now().toIso8601String();
    final body = <String, Object?>{
      'name': name,
      'note': _note.text.trim(),
      'schedule': _weekly ? 'weekly' : 'daily',
      'target': _weekly ? _target : 1,
      // An edit keeps the habit's life story: still archived or not, still
      // born when it was born. Only the person's words and the schedule
      // change.
      'archived': widget.habit?.archived ?? false,
      'createdAt': widget.habit?.createdAt.toIso8601String() ?? now,
    };
    final id = _recordId;
    final saved = await storeWrite(context, () async {
      await widget.store.put('habit', id, body);
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
    final strings = habitsStrings;
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
                  strings(context, _editing ? 'editHabit' : 'newHabit'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.md),
                // A person's own words, one line: the direction follows the script
                // they type, as everywhere in Nex.
                NexAutoDirection(
                  controller: _name,
                  builder: (context, _) => TextField(
                    key: const ValueKey('habit-field-name'),
                    controller: _name,
                    autofocus: !_editing,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      if (_nameError != null) {
                        setState(() => _nameError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: strings(context, 'nameLabel'),
                      hintText: strings(context, 'nameHint'),
                      errorText: _nameError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                NexTextField(
                  key: const ValueKey('habit-field-note'),
                  controller: _note,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: strings(context, 'noteLabel'),
                    hintText: strings(context, 'noteHint'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                AdaptiveSegments<bool>(
                  key: const ValueKey('habit-field-schedule'),
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.today_outlined),
                      label: Text(strings(context, 'daily')),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(strings(context, 'weekly')),
                    ),
                  ],
                  selected: {_weekly},
                  onSelectionChanged: _saving
                      ? null
                      : (value) => setState(() => _weekly = value.first),
                ),
                if (_weekly) ...[
                  const SizedBox(height: NexSpacing.md),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: NexSpacing.sm,
                      runSpacing: NexSpacing.sm,
                      children: [
                        for (var n = 1; n <= 7; n++)
                          ChoiceChip(
                            key: ValueKey('habit-target-$n'),
                            label: Text(
                              // "1 times a week" is no-one's English; the
                              // singular chip says it properly.
                              strings(
                                context,
                                n == 1 ? 'oneTarget' : 'targetLabel',
                                {'n': n},
                              ),
                            ),
                            selected: _target == n,
                            onSelected: _saving
                                ? null
                                : (selected) {
                                    if (selected) setState(() => _target = n);
                                  },
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: NexSpacing.lg),
                FilledButton(
                  key: const ValueKey('habit-save'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _saving ? null : () => _save(),
                  child: _saving
                      ? const NexInlineSpinner(size: 20)
                      : Text(l10n.save),
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
