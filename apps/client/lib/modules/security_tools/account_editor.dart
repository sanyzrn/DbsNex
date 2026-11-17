import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'account_guard.dart';
import 'account_model.dart';
import 'account_repository.dart';
import 'security_strings.dart';

class SecurityAccountEditor extends StatefulWidget {
  const SecurityAccountEditor({super.key, required this.repo, this.account});
  final AccountRepository repo;
  final SecurityAccount? account;
  @override
  State<SecurityAccountEditor> createState() => _SecurityAccountEditorState();
}

class _SecurityAccountEditorState extends State<SecurityAccountEditor> {
  late final _label = TextEditingController(text: widget.account?.label ?? '');
  late final _states = {
    for (final k in securityChecks) k: widget.account?.state(k) ?? 'unknown',
  };
  final _changed = <String>{};
  late String _id = widget.account?.id ?? widget.repo.store.newId();
  late final _copyId = widget.repo.store.newId();
  late final _draft = NexModuleFormDraft(
    widget.repo.store,
    'account:${widget.account?.id ?? 'new'}',
    widget.account?.raw ?? const {},
    {'label': _label},
    () => {
      'recordId': _id,
      'checks': Map<String, String>.of(_states),
      'changed': _changed.toList(),
    },
  );
  bool _loading = true, _failed = false, _saving = false, _conflict = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final data = await _draft.load();
    if (!mounted) return;
    if (_draft.loadFailed) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    if (data != null) {
      final savedId = data['recordId'];
      if (widget.account == null &&
          savedId is String &&
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(savedId)) {
        _id = savedId;
      }
      _draft.apply(data);
      final choices = data['checks'];
      if (choices is Map) {
        for (final k in securityChecks) {
          if (checkStates.contains(choices[k])) {
            _states[k] = choices[k] as String;
          }
        }
      }
      final changed = data['changed'];
      if (changed is List) {
        _changed.addAll(
          changed.whereType<String>().where(securityChecks.contains),
        );
      }
    }
    _draft.start();
    setState(() {
      _loading = false;
      _failed = false;
    });
  }

  @override
  void dispose() {
    _draft.close();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save({bool copy = false}) async {
    if (_loading || _saving || _failed) return;
    if (_label.text.trim().isEmpty || _label.text.length > 60) {
      setState(() => _error = securityStrings(context, 'required'));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.save(
        copy ? _copyId : _id,
        copy ? null : widget.account?.raw,
        _label.text,
        {
          for (final k in securityChecks)
            if (copy || widget.account == null || _changed.contains(k))
              k: _states[k]!,
        },
      );
      await _draft.clear();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _conflict = e is SecurityConflict;
          _error = securityStrings(
            context,
            _conflict ? 'conflict' : 'saveError',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = securityStrings;
    return AccountDraftGuard(
      draft: _draft,
      busy: () => _loading || _saving,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(
            s(context, widget.account == null ? 'addAccount' : 'edit'),
          ),
        ),
        body: _failed
            ? NexEmptyState(
                icon: Icons.refresh,
                message: s(context, 'loadError'),
                action: TextButton(
                  onPressed: _load,
                  child: Text(s(context, 'retry')),
                ),
              )
            : AbsorbPointer(
                absorbing: _loading || _saving,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    NexSpacing.md,
                    NexSpacing.md,
                    NexSpacing.md,
                    NexSpacing.xl + nexBottomInset(context),
                  ),
                  children: [
                    Text(s(context, 'accountPrivacy')),
                    const SizedBox(height: NexSpacing.md),
                    NexTextField(
                      key: const ValueKey('security-label'),
                      controller: _label,
                      minLines: 1,
                      maxLines: 2,
                      maxLength: 60,
                      enableIMEPersonalizedLearning: false,
                      decoration: InputDecoration(
                        labelText: s(context, 'label'),
                        hintText: s(context, 'labelHint'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: NexSpacing.md),
                    for (final k in securityChecks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: NexSpacing.md),
                        child: NexPanel(
                          title: s(context, k),
                          icon: Icons.fact_check_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s(context, '${k}Help')),
                              const SizedBox(height: NexSpacing.sm),
                              NexAdaptiveSegments<String>(
                                key: ValueKey('security-check-$k'),
                                segments: [
                                  for (final state in checkStates)
                                    ButtonSegment(
                                      value: state,
                                      label: Text(s(context, state)),
                                    ),
                                ],
                                selected: {_states[k]!},
                                onSelectionChanged: (v) {
                                  setState(() {
                                    _states[k] = v.first;
                                    _changed.add(k);
                                  });
                                  _draft.changed();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    FilledButton(
                      key: const ValueKey('security-save'),
                      onPressed: _save,
                      child: Text(s(context, 'save')),
                    ),
                    if (_conflict)
                      TextButton(
                        onPressed: () => _save(copy: true),
                        child: Text(s(context, 'saveCopy')),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
