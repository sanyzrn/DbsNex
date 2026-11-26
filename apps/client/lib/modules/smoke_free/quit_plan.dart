import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'draft_guard.dart';
import 'form_draft.dart';
import 'module.dart';
import 'quit_model.dart';
import 'store_state.dart';

class QuitPlanCard extends StatelessWidget {
  const QuitPlanCard({super.key, required this.attempt, required this.store});
  final QuitAttempt attempt;
  final NexModuleStore store;
  @override
  Widget build(BuildContext context) => NexPanel(
    key: const ValueKey('quit-plan-card'),
    title: smokeFreeStrings(context, 'planTitle'),
    icon: Icons.route_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NexTextDirection(
          text: attempt.nextStep,
          child: Text(
            attempt.nextStep.isEmpty
                ? smokeFreeStrings(context, 'planEmpty')
                : attempt.nextStep,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        TextButton.icon(
          key: const ValueKey('quit-plan-edit'),
          icon: const Icon(Icons.edit_outlined),
          label: Text(
            smokeFreeStrings(
              context,
              attempt.nextStep.isEmpty ? 'planCreate' : 'planEdit',
            ),
          ),
          onPressed: () => nexShowSheet<void>(
            context: context,
            dismissible: false,
            swipeToClose: true,
            builder: (_) => _PlanEditor(store: store, attempt: attempt),
          ),
        ),
      ],
    ),
  );
}

class _PlanEditor extends StatefulWidget {
  const _PlanEditor({required this.store, required this.attempt});
  final NexModuleStore store;
  final QuitAttempt attempt;
  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  late final _text = TextEditingController(text: widget.attempt.nextStep);
  late final _draft = FormDraft(
    widget.store,
    'plan:${widget.attempt.id}',
    {'nextStep': widget.attempt.nextStep},
    {'nextStep': _text},
    () => const {},
  );
  bool _loading = true, _failed = false, _saving = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final saved = await _draft.load();
    if (!mounted) return;
    if (_draft.loadFailed) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    if (saved != null) _draft.apply(saved);
    _draft.start();
    setState(() {
      _loading = false;
      _failed = false;
    });
  }

  @override
  void dispose() {
    _draft.close();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _loading || _failed) return;
    setState(() => _saving = true);
    final saved = await storeWrite(context, () async {
      final prior = await widget.store.get('quit', widget.attempt.id);
      if (prior == null) throw StateError('attempt unavailable');
      await widget.store.put('quit', widget.attempt.id, {
        ...prior,
        'nextStep': _text.text.trim(),
        'v': 3,
      });
    });
    if (!mounted) return;
    if (saved) {
      try {
        await _draft.clear();
      } catch (_) {
        // The saved record is authoritative; a stale draft is not a reason
        // to strand the sheet or pretend the save failed.
      }
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    draft: _draft,
    busy: () => _saving || _loading,
    child: _failed
        ? NexEmptyState(
            icon: Icons.refresh,
            message: smokeFreeStrings(context, 'draftReadFailed'),
            action: TextButton(
              onPressed: () {
                setState(() => _loading = true);
                unawaited(_load());
              },
              child: Text(smokeFreeStrings(context, 'retry')),
            ),
          )
        : AbsorbPointer(
            absorbing: _loading || _saving,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(NexSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    smokeFreeStrings(context, 'planTitle'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Text(smokeFreeStrings(context, 'planHint')),
                  const SizedBox(height: NexSpacing.md),
                  NexTextField(
                    key: const ValueKey('quit-plan-field'),
                    controller: _text,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: smokeFreeStrings(context, 'planLabel'),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  FilledButton(
                    key: const ValueKey('quit-plan-save'),
                    onPressed: _save,
                    child: Text(AppLocalizations.of(context).save),
                  ),
                ],
              ),
            ),
          ),
  );
}
