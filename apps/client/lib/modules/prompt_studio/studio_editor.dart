import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'prompt_model.dart';
import 'studio_guard.dart';
import 'studio_repository.dart';
import 'studio_strings.dart';

class StudioEditor extends StatefulWidget {
  const StudioEditor({
    super.key,
    required this.repo,
    this.entry,
    this.seed = const {},
    this.draftKey,
  });
  final StudioRepository repo;
  final PromptEntry? entry;
  final Map<String, Object?> seed;
  final String? draftKey;
  @override
  State<StudioEditor> createState() => _StudioEditorState();
}

class _StudioEditorState extends State<StudioEditor> {
  late final Map<String, TextEditingController> _fields;
  late final NexModuleFormDraft _draft;
  late final String _id = widget.entry?.id ?? widget.repo.store.newId();
  bool _loading = true, _failed = false, _saving = false;
  bool _block = false, _favorite = false;
  String? _error;
  bool _conflicted = false;
  late bool _details = widget.entry != null;
  late final _copyId = widget.repo.store.newId();
  Timer? _preview;
  @override
  void initState() {
    super.initState();
    final initial = {...?widget.entry?.raw, ...widget.seed};
    _fields = {
      for (final key in ['title', 'body', 'category', 'notes'])
        key: TextEditingController(
          text: initial[key] is String ? initial[key] as String : '',
        ),
    };
    _block = initial['block'] == true;
    _favorite = initial['favorite'] == true;
    _draft = NexModuleFormDraft(
      widget.repo.store,
      widget.entry != null
          ? 'entry:${widget.entry!.id}'
          : 'entry:${widget.draftKey ?? (_block ? 'block' : 'prompt')}:new',
      widget.entry?.raw ??
          (widget.seed.containsKey('body') ? widget.seed : const {}),
      _fields,
      () => {
        'block': _block,
        'favorite': _favorite,
        'details': _details,
        'recordId': _id,
      },
    );
    _fields['body']!.addListener(_bodyChanged);
    unawaited(_load());
  }

  void _bodyChanged() {
    _preview?.cancel();
    _preview = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() {});
    });
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
    if (saved != null) {
      _draft.apply(saved);
      _block = saved['block'] == true;
      _favorite = saved['favorite'] == true;
      _details = widget.entry != null || saved['details'] == true;
    }
    _draft.start();
    if (widget.seed.isNotEmpty && saved == null) _draft.changed();
    setState(() {
      _loading = false;
      _failed = false;
    });
  }

  @override
  void dispose() {
    _preview?.cancel();
    _draft.close();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool asCopy = false}) async {
    if (_loading || _saving || _failed) return;
    final data = {
      for (final e in _fields.entries)
        e.key: (e.key == 'title' || e.key == 'category')
            ? e.value.text.trim()
            : e.value.text,
      'block': _block,
      'favorite': _favorite,
      'v': 1,
    };
    final candidate = PromptEntry(_id, data);
    if (!candidate.valid || PromptTemplate(candidate.body).slots.length > 24) {
      setState(
        () => _error = studioStrings(
          context,
          PromptTemplate(candidate.body).slots.length > 24
              ? 'tooMany'
              : 'required',
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.save(
        asCopy ? _copyId : _id,
        asCopy ? null : widget.entry?.raw,
        data,
      );
      await _draft.clear();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _conflicted = e is StudioConflict;
          _error = studioStrings(
            context,
            e is StudioConflict ? 'conflict' : 'saveError',
          );
        });
      }
    }
  }

  Future<void> _blocks() async {
    try {
      final records = await widget.repo.store.list('entry');
      if (!mounted) return;
      final blocks = records
          .map(PromptEntry.fromRecord)
          .where((e) => e.block && e.valid && e.id != _id)
          .toList();
      final chosen = await nexShowSheet<PromptEntry>(
        context: context,
        builder: (c) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(NexSpacing.md),
          children: [
            Text(studioStrings(c, 'blockHint')),
            if (blocks.isEmpty) Text(studioStrings(c, 'noBlocks')),
            for (final b in blocks)
              ListTile(title: Text(b.title), onTap: () => Navigator.pop(c, b)),
          ],
        ),
      );
      if (chosen == null || !mounted) return;
      final controller = _fields['body']!;
      final selection = controller.selection;
      final start = selection.isValid
          ? selection.start.clamp(0, controller.text.length)
          : controller.text.length;
      final end = selection.isValid
          ? selection.end.clamp(start, controller.text.length)
          : start;
      final next = controller.text.replaceRange(start, end, chosen.body);
      if (next.length > 50000) {
        setState(() => _error = studioStrings(context, 'required'));
        return;
      }
      controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + chosen.body.length),
      );
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: studioStrings(context, 'loadError'),
          kind: NexBannerKind.failed,
        );
      }
    }
  }

  Future<void> _history() async {
    final revisions = widget.entry?.history ?? [];
    final chosen = await nexShowSheet<Map<String, Object?>>(
      context: context,
      builder: (c) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(NexSpacing.md),
        children: [
          Text(studioStrings(c, 'historyHint')),
          if (revisions.isEmpty) Text(studioStrings(c, 'historyEmpty')),
          for (final r in revisions)
            ListTile(
              title: Text(r['title'] as String),
              subtitle: Text(
                r['body'] as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(c, r),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final confirm = await nexShowDialog<bool>(
      context: context,
      builder: (c) => NexAlertDialog(
        title: Text(studioStrings(c, 'restore')),
        content: NexDialogBody(child: Text(studioStrings(c, 'historyHint'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(c).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(studioStrings(c, 'restore')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    for (final key in _fields.keys) {
      if (chosen[key] is String) _fields[key]!.text = chosen[key] as String;
    }
  }

  Widget _field(String key, int limit, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: NexSpacing.md),
    child: NexTextField(
      key: ValueKey('studio-$key'),
      controller: _fields[key]!,
      minLines: lines,
      maxLines: key == 'body' ? 16 : lines,
      maxLength: limit,
      enableIMEPersonalizedLearning: false,
      decoration: InputDecoration(
        counterText: studioStrings(context, 'limit', {'n': limit}),
        labelText: studioStrings(context, key == 'title' ? 'entryTitle' : key),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final s = studioStrings;
    return StudioGuard(
      draft: _draft,
      busy: () => _loading || _saving,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(
            s(
              context,
              widget.entry != null
                  ? 'edit'
                  : _block
                  ? 'newBlock'
                  : 'new',
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
                absorbing: _loading || _saving,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    NexSpacing.md,
                    NexSpacing.md,
                    NexSpacing.md,
                    NexSpacing.xl + nexBottomInset(context),
                  ),
                  children: [
                    _field('title', 100),
                    Text(
                      s(context, 'syntax'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    _field('body', 50000, lines: 6),
                    Text(
                      s(
                        context,
                        PromptTemplate(_fields['body']!.text).slots.length == 1
                            ? 'slotOne'
                            : 'slots',
                        {
                          'n': PromptTemplate(_fields['body']!.text)
                              .slots
                              .length,
                        },
                      ),
                    ),
                    Wrap(
                      spacing: NexSpacing.sm,
                      children: [
                        TextButton.icon(
                          key: const ValueKey('studio-insert'),
                          onPressed: _blocks,
                          icon: const Icon(Icons.extension_outlined),
                          label: Text(s(context, 'insertBlock')),
                        ),
                        if (widget.entry != null)
                          TextButton.icon(
                            onPressed: _history,
                            icon: const Icon(Icons.history),
                            label: Text(s(context, 'history')),
                          ),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.md),
                    NexMoreDetails(
                      open: _details,
                      onChanged: (v) {
                        setState(() => _details = v);
                        _draft.changed();
                      },
                      title: s(context, 'details'),
                      child: Column(
                        children: [
                          _field('category', 40),
                          _field('notes', 2000, lines: 3),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(s(context, 'blockLabel')),
                            value: _block,
                            onChanged: (v) {
                              setState(() => _block = v);
                              _draft.changed();
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(s(context, 'favorite')),
                            value: _favorite,
                            onChanged: (v) {
                              setState(() => _favorite = v);
                              _draft.changed();
                            },
                          ),
                        ],
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
                      key: const ValueKey('studio-save'),
                      onPressed: _save,
                      child: Text(s(context, 'save')),
                    ),
                    if (_conflicted)
                      TextButton(
                        onPressed: () => _save(asCopy: true),
                        child: Text(s(context, 'duplicate')),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
