import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'craving_rating.dart';
import 'adaptive_segments.dart';
import 'store_state.dart';
import 'form_draft.dart';
import 'draft_guard.dart';
import 'quit_model.dart';

/// Logs or edits a craving with optional after-rating and deletion Undo.
Future<void> showCravingSheet(
  BuildContext context,
  NexModuleStore store, {
  Craving? editing,
  String habit = defaultHabit,
  int? initialIntensity,
  String? initialCoping,
  int? afterIntensity,
}) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (context) => _CravingSheet(
    store: store,
    editing: editing,
    habit: habit,
    initialIntensity: initialIntensity,
    initialCoping: initialCoping,
    afterIntensity: afterIntensity,
  ),
);

class _CravingSheet extends StatefulWidget {
  const _CravingSheet({
    required this.store,
    required this.editing,
    required this.habit,
    this.initialIntensity,
    this.initialCoping,
    this.afterIntensity,
  });

  final NexModuleStore store;
  final Craving? editing;

  /// The habit a new craving belongs to; an edited one keeps its own.
  final String habit;
  final int? initialIntensity, afterIntensity;
  final String? initialCoping;

  @override
  State<_CravingSheet> createState() => _CravingSheetState();
}

class _CravingSheetState extends State<_CravingSheet> {
  late final TextEditingController _note;
  late int _intensity;
  late final Set<String> _triggers;
  String? _coping;
  int? _afterIntensity;
  bool _loadFailed = false;
  bool _saving = false;
  bool _restoring = true;
  late final FormDraft _draft;
  late final String _recordId = widget.editing?.id ?? widget.store.newId();

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _note = TextEditingController(text: editing?.note ?? '');
    _intensity = editing?.intensity ?? widget.initialIntensity ?? 2;
    _triggers = {...?editing?.triggers};
    _coping = editing?.coping ?? widget.initialCoping;
    _afterIntensity = editing?.afterIntensity ?? widget.afterIntensity;
    _draft = FormDraft(
      widget.store,
      editing != null
          ? 'craving:${editing.id}'
          : widget.habit == defaultHabit
          ? 'craving:new'
          : 'craving:${widget.habit}:new',
      editing?.toJson() ?? const {},
      {'note': _note},
      () => {
        'recordId': _recordId,
        'intensity': _intensity,
        'triggers': _triggers.toList(),
        'coping': _coping,
        'afterIntensity': _afterIntensity,
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
      final after = body['afterIntensity'];
      _afterIntensity = after is int && after >= 1 && after <= 3 ? after : null;
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
    // SOS ratings are user input even if the person leaves without typing.
    if (body == null && widget.initialIntensity != null) _draft.changed();
    setState(() {
      _restoring = false;
      _loadFailed = false;
    });
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
      if (_afterIntensity != null || widget.editing?.afterIntensity != null)
        'afterIntensity': _afterIntensity,
      'triggers': _triggers.toList(),
      'coping': _coping,
      'note': _note.text.trim(),
      // Keep legacy cigarette records without a habit key.
      if ((widget.editing?.habit ?? widget.habit) != defaultHabit)
        'habit': widget.editing?.habit ?? widget.habit,
    };
    final id = _recordId;
    final saved = await storeWrite(context, () async {
      final prior = await widget.store.get('craving', id);
      await widget.store.put('craving', id, {...?prior, ...body});
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
    final messenger = NexBannerHost.of(context);
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
    messenger?.show(
      message: smokeFreeStrings(context, 'cravingDeleted'),
      actionLabel: l10n.undo,
      onAction: () =>
          widget.store.put('craving', editing.id, raw).catchError((Object _) {
            messenger.show(kind: NexBannerKind.failed, message: errorMessage);
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_restoring && !_loadFailed) _draft.changed();
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final editing = widget.editing != null;
    return DraftGuard(
      draft: _draft,
      busy: () => _saving,
      child: _loadFailed
          ? NexEmptyState(
              icon: Icons.refresh,
              message: strings(context, 'draftReadFailed'),
              action: TextButton(
                onPressed: () {
                  setState(() => _restoring = true);
                  unawaited(_restoreDraft());
                },
                child: Text(strings(context, 'retry')),
              ),
            )
          : AbsorbPointer(
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
                            : (value) =>
                                  setState(() => _intensity = value.first),
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
                                      setState(
                                        () => _coping = selected ? key : null,
                                      );
                                    },
                            ),
                        ],
                      ),
                      const SizedBox(height: NexSpacing.md),
                      if (_coping != null || _afterIntensity != null) ...[
                        CravingRating(
                          label: strings(context, 'afterRating'),
                          value: _afterIntensity,
                          onChanged: (value) =>
                              setState(() => _afterIntensity = value),
                        ),
                        const SizedBox(height: NexSpacing.md),
                      ],
                      NexTextField(
                        key: const ValueKey('craving-field-note'),
                        controller: _note,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: strings(context, 'noteLabel'),
                          hintText: strings(context, 'noteHint'),
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
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
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
