import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'prompt_model.dart';
import 'studio_editor.dart';
import 'studio_guard.dart';
import 'studio_repository.dart';
import 'studio_strings.dart';

class StudioWorkbench extends StatefulWidget {
  const StudioWorkbench({super.key, required this.repo, required this.entry});
  final StudioRepository repo;
  final PromptEntry entry;
  @override
  State<StudioWorkbench> createState() => _StudioWorkbenchState();
}

class _StudioWorkbenchState extends State<StudioWorkbench> {
  late final _template = PromptTemplate(widget.entry.body);
  late final _fields = {
    for (final s in _template.slots.take(24)) s: TextEditingController(),
  };
  late final _draft = NexModuleFormDraft(
    widget.repo.store,
    'fill:${widget.entry.id}',
    {'body': widget.entry.body},
    _fields,
    () => const {},
  );
  bool _loading = true, _failed = false, _busy = false;
  Timer? _refresh;
  Map<String, String> get _values => {
    for (final e in _fields.entries) e.key: e.value.text,
  };
  @override
  void initState() {
    super.initState();
    for (final f in _fields.values) {
      f.addListener(_changed);
    }
    unawaited(_load());
  }

  void _changed() {
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
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
    if (data != null) _draft.apply(data);
    // Focus and selection changes notify the controllers too. Store a new
    // checkpoint only after the loaded values have actually changed.
    _draft.resume(markCurrentAsClean: true);
    setState(() {
      _loading = false;
      _failed = false;
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _draft.close();
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _copy() async {
    final values = _values;
    if (_busy ||
        _loading ||
        _failed ||
        _template.slots.length > 24 ||
        _template.missing(values).isNotEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      await nexModuleCopyText(_template.fill(values));
      final cleared = await _draft.clear();
      if (!mounted) return;
      final changedWhileCopying = !mapEquals(values, _values);
      _draft.resume(markCurrentAsClean: cleared && !changedWhileCopying);
      if (changedWhileCopying) _draft.changed();
      nexShowBanner(
        context,
        message: studioStrings(context, cleared ? 'copied' : 'copyClearError'),
        kind: cleared ? NexBannerKind.done : NexBannerKind.failed,
      );
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: studioStrings(context, 'copyError'),
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final yes = await nexShowDialog<bool>(
      context: context,
      builder: (c) => NexAlertDialog(
        title: Text(studioStrings(c, 'clearAsk')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(c).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(studioStrings(c, 'clear')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    for (final f in _fields.values) {
      f.clear();
    }
  }

  Future<void> _edit() async {
    if (_busy || _loading) return;
    setState(() => _busy = true);
    if (!await _draft.finish()) {
      _draft.resume();
      if (mounted) {
        setState(() => _busy = false);
        nexShowBanner(
          context,
          message: studioStrings(context, 'saveError'),
          kind: NexBannerKind.failed,
        );
      }
      return;
    }
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        NexPageRoute(
          builder: (_) => StudioEditor(repo: widget.repo, entry: widget.entry),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = studioStrings;
    final missing = _template.missing(_values);
    final ready = missing.isEmpty && _template.slots.length <= 24;
    final result = _template.fill(_values);
    return StudioGuard(
      draft: _draft,
      busy: () => _loading || _busy,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(widget.entry.title),
          actions: [
            IconButton(
              onPressed: _busy || _failed ? null : _edit,
              tooltip: s(context, 'edit'),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        bottomNavigationBar: _failed
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(NexSpacing.md),
                  child: FilledButton.icon(
                    key: const ValueKey('studio-copy'),
                    onPressed: ready && !_loading && !_busy ? _copy : null,
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(s(context, 'copy')),
                  ),
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
                absorbing: _loading || _busy,
                child: ListView(
                  padding: const EdgeInsets.all(NexSpacing.md),
                  children: [
                    NexModuleHero(
                      moduleId: 'prompt_studio',
                      icon: Icons.tune_outlined,
                      eyebrow: s(context, 'fill'),
                      headline: s(
                        context,
                        ready
                            ? 'ready'
                            : missing.length == 1
                            ? 'remainingOne'
                            : 'remaining',
                        {'n': missing.length},
                      ),
                      caption: s(context, 'syntax'),
                    ),
                    const SizedBox(height: NexSpacing.md),
                    if (_template.slots.length > 24)
                      Text(s(context, 'tooMany')),
                    if (_fields.isEmpty) Text(s(context, 'noSlots')),
                    for (final e in _fields.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: NexSpacing.md),
                        child: NexTextField(
                          key: ValueKey('fill-${e.key}'),
                          controller: e.value,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 4000,
                          enableIMEPersonalizedLearning: false,
                          decoration: InputDecoration(
                            labelText: e.key,
                            counterText: s(context, 'limit', {'n': 4000}),
                          ),
                        ),
                      ),
                    if (_fields.isNotEmpty)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: _clear,
                          child: Text(s(context, 'clear')),
                        ),
                      ),
                    const SizedBox(height: NexSpacing.md),
                    NexPanel(
                      title: s(context, 'preview'),
                      icon: Icons.visibility_outlined,
                      child: NexTextDirection(
                        text: result,
                        child: SelectableText(
                          result,
                          key: const ValueKey('studio-preview'),
                        ),
                      ),
                    ),
                    const SizedBox(height: NexSpacing.md),
                  ],
                ),
              ),
      ),
    );
  }
}
