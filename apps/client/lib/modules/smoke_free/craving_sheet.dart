import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'adaptive_segments.dart';
import 'store_state.dart';
import 'form_draft.dart';
import 'draft_guard.dart';
import 'quit_model.dart';

/// Logs a craving in one open: intensity, what set it off, what helped, a
/// short note. The same sheet, prefilled, edits an existing craving; a
/// delete with Undo lives here too.
Future<void> showCravingSheet(
  BuildContext context,
  NexModuleStore store, {
  Craving? editing,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (context) => _CravingSheet(store: store, editing: editing),
);

class _CravingSheet extends StatefulWidget {
  const _CravingSheet({required this.store, required this.editing});

  final NexModuleStore store;
  final Craving? editing;

  @override
  State<_CravingSheet> createState() => _CravingSheetState();
}

class _CravingSheetState extends State<_CravingSheet> {
  late final TextEditingController _note;
  late int _intensity;
  late final Set<String> _triggers;
  String? _coping;
  bool _saving = false;
  bool _restoring = true;
  late final FormDraft _draft;
  late final String _recordId = widget.editing?.id ?? widget.store.newId();

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _note = TextEditingController(text: editing?.note ?? '');
    _intensity = editing?.intensity ?? 2;
    _triggers = {...?editing?.triggers};
    _coping = editing?.coping;
    _draft = FormDraft(
      widget.store,
      'craving:${editing?.id ?? 'new'}',
      editing?.toJson() ?? const {},
      {'note': _note},
      () => {
        'recordId': _recordId,
        'intensity': _intensity,
        'triggers': _triggers.toList(),
        'coping': _coping,
      },
    );
    unawaited(_restoreDraft());
  }

  Future<void> _restoreDraft() async {
    final body = await _draft.load();
    if (!mounted) return;
    if (body != null) {
      _draft.apply(body);
      final intensity = body['intensity'];
      if (intensity is int) _intensity = intensity.clamp(1, 3);
      final triggers = body['triggers'];
      if (triggers is List) {
        _triggers.clear();
        _triggers.addAll(
          triggers.whereType<String>().where(cravingTriggerKeys.contains),
        );
      }
      _coping = cravingCopingKeys.contains(body['coping'])
          ? body['coping'] as String
          : null;
    }
    _draft.start();
    setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _draft.close();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final body = <String, Object?>{
      'at':
          widget.editing?.at.toIso8601String() ??
          DateTime.now().toIso8601String(),
      'intensity': _intensity,
      'triggers': _triggers.toList(),
      'coping': _coping,
      'note': _note.text.trim(),
    };
    final id = _recordId;
    final saved = await storeWrite(context, () async {
      await widget.store.put('craving', id, body);
    });
    if (!mounted) return;
    if (!saved) setState(() => _saving = false);
    if (saved) {
      await _draft.clear();
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop();
      }
    }
  }

  /// Deletes the craving being edited, with an Undo that restores the
  /// whole record.
  Future<void> _delete() async {
    final editing = widget.editing;
    if (editing == null || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final errorMessage = smokeFreeStrings(context, 'saveError');
    Map<String, Object?>? snapshot;
    final deleted = await storeWrite(context, () async {
      snapshot = await widget.store.get('craving', editing.id);
      if (snapshot != null) await widget.store.delete('craving', editing.id);
    });
    if (!mounted) return;
    final raw = snapshot;
    if (!deleted || raw == null) {
      setState(() => _saving = false);
      return;
    }
    await _draft.clear();
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(smokeFreeStrings(context, 'cravingDeleted')),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => widget.store
              .put('craving', editing.id, raw)
              .catchError((Object _) {
                messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
              }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_restoring) _draft.changed();
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final editing = widget.editing != null;
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
                  strings(context, 'cravingTitle'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.md),
                Text(
                  strings(context, 'intensity'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: NexSpacing.sm),
                AdaptiveSegments<int>(
                  key: const ValueKey('craving-intensity'),
                  segments: [
                    ButtonSegment(
                      value: 1,
                      label: Text(strings(context, 'intensityLow')),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text(strings(context, 'intensityMedium')),
                    ),
                    ButtonSegment(
                      value: 3,
                      label: Text(strings(context, 'intensityHigh')),
                    ),
                  ],
                  selected: {_intensity},
                  onSelectionChanged: _saving
                      ? null
                      : (value) => setState(() => _intensity = value.first),
                ),
                const SizedBox(height: NexSpacing.md),
                Text(
                  strings(context, 'triggers'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: NexSpacing.sm),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final key in cravingTriggerKeys)
                      FilterChip(
                        key: ValueKey('craving-trigger-$key'),
                        label: Text(triggerLabel(context, key)),
                        selected: _triggers.contains(key),
                        onSelected: _saving
                            ? null
                            : (selected) {
                                setState(() {
                                  selected
                                      ? _triggers.add(key)
                                      : _triggers.remove(key);
                                });
                              },
                      ),
                  ],
                ),
                const SizedBox(height: NexSpacing.md),
                Text(
                  strings(context, 'coping'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: NexSpacing.sm),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final key in cravingCopingKeys)
                      ChoiceChip(
                        key: ValueKey('craving-coping-$key'),
                        label: Text(copingLabel(context, key)),
                        selected: _coping == key,
                        onSelected: _saving
                            ? null
                            : (selected) {
                                setState(() => _coping = selected ? key : null);
                              },
                      ),
                  ],
                ),
                const SizedBox(height: NexSpacing.md),
                NexTextField(
                  key: const ValueKey('craving-field-note'),
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
                const SizedBox(height: NexSpacing.lg),
                FilledButton(
                  key: const ValueKey('craving-save'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _saving ? null : () => _save(),
                  child: _saving
                      ? const NexInlineSpinner(size: 20)
                      : Text(l10n.save),
                ),
                if (editing) ...[
                  const SizedBox(height: NexSpacing.sm),
                  TextButton(
                    key: const ValueKey('craving-delete'),
                    onPressed: _saving ? null : () => _delete(),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: Text(strings(context, 'deleteCraving')),
                  ),
                ],
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

/// The localized label of a trigger key, from the module's own words.
String triggerLabel(BuildContext context, String key) =>
    smokeFreeStrings(context, 'trigger_$key');

/// The localized label of a coping key.
String copingLabel(BuildContext context, String key) =>
    smokeFreeStrings(context, 'coping_$key');
