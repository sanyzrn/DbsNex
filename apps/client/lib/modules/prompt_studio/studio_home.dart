import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'prompt_model.dart';
import 'studio_editor.dart';
import 'studio_repository.dart';
import 'studio_strings.dart';
import 'studio_workbench.dart';

class StudioHome extends StatefulWidget {
  const StudioHome({super.key, required this.store});
  final NexModuleStore store;
  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  late final repo = StudioRepository(widget.store);
  final _search = TextEditingController();
  StreamSubscription<void>? _changes;
  VoidCallback? _hideUndo;
  List<PromptEntry> _items = [];
  bool _loading = true, _failed = false, _busy = false;
  Timer? _searchDelay;
  int _filter = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = ++_generation;
    try {
      final rows = await widget.store.list('entry');
      if (!mounted || token != _generation) return;
      setState(() {
        _items = rows.map(PromptEntry.fromRecord).toList();
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted && token == _generation) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchDelay?.cancel();
    _hideUndo?.call();
    unawaited(_changes?.cancel());
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit({
    PromptEntry? entry,
    Map<String, Object?>? seed,
    String? draftKey,
  }) => Navigator.of(context).push<void>(
    NexPageRoute(
      builder: (_) => StudioEditor(
        repo: repo,
        entry: entry,
        draftKey: draftKey,
        seed: seed ?? {'block': _filter == 2},
      ),
    ),
  );
  Future<void> _action(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        nexShowBanner(
          context,
          message: studioStrings(
            context,
            e is StudioConflict ? 'conflict' : 'saveError',
          ),
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PromptEntry entry) async {
    final confirm = await nexShowDialog<bool>(
      context: context,
      builder: (c) => NexAlertDialog(
        title: Text(studioStrings(c, 'deleteAsk')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(AppLocalizations.of(c).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(studioStrings(c, 'delete')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _action(() async {
      final raw = await repo.delete(entry);
      if (!mounted) return;
      final handle = nexShowBanner(
        context,
        message: studioStrings(context, 'deleted'),
        actionLabel: studioStrings(context, 'undo'),
        onAction: () => unawaited(_action(() => repo.undo(entry.id, raw))),
      );
      _hideUndo = handle?.hide;
    });
  }

  Widget _tile(PromptEntry entry) => Padding(
    padding: const EdgeInsets.only(bottom: NexSpacing.sm),
    child: NexPanel(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          entry.favorite
              ? Icons.star
              : entry.block
              ? Icons.extension_outlined
              : Icons.notes_outlined,
        ),
        title: NexTextDirection(
          text: entry.title,
          child: Text(
            entry.title.isEmpty
                ? studioStrings(context, 'untitled')
                : entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        subtitle: Text(
          !entry.valid
              ? studioStrings(context, 'invalid')
              : [
                  if (entry.category.isNotEmpty) entry.category,
                  studioStrings(
                    context,
                    entry.slotCount == 1 ? 'slotOne' : 'slots',
                    {'n': entry.slotCount},
                  ),
                ].join(' · '),
        ),
        onTap: _busy
            ? null
            : () => !entry.valid || entry.block
                  ? _edit(entry: entry)
                  : Navigator.of(context).push<void>(
                      NexPageRoute(
                        builder: (_) =>
                            StudioWorkbench(repo: repo, entry: entry),
                      ),
                    ),
        trailing: NexPopupMenuButton<String>(
          tooltip: studioStrings(context, 'more'),
          icon: const Icon(Icons.more_horiz),
          onSelected: (v) {
            if (_busy) return;
            if (v == 'edit') unawaited(_edit(entry: entry));
            if (v == 'duplicate') {
              unawaited(
                _edit(
                  seed: promptRevision(entry.raw),
                  draftKey: 'copy:${entry.id}',
                ),
              );
            }
            if (v == 'delete') unawaited(_delete(entry));
          },
          itemBuilder: (c) => [
            for (final pair in [
              ('edit', Icons.edit_outlined),
              ('duplicate', Icons.copy_outlined),
              ('delete', Icons.delete_outline),
            ])
              nexMenuItem(
                value: pair.$1,
                icon: pair.$2,
                label: studioStrings(c, pair.$1),
              ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final s = studioStrings;
    final visible = _items
        .where(
          (e) =>
              e.matches(_search.text) &&
              (_filter == 0
                  ? !e.block
                  : _filter == 1
                  ? e.favorite
                  : e.block),
        )
        .toList();
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'title'))),
      floatingActionButton: _loading || _failed
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('studio-add'),
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(s(context, _filter == 2 ? 'newBlock' : 'new')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? NexEmptyState(
              icon: Icons.refresh,
              message: s(context, 'loadError'),
              action: TextButton(
                onPressed: _load,
                child: Text(s(context, 'retry')),
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.xl * 4 + nexBottomInset(context),
              ),
              children: [
                NexModuleHero(
                  moduleId: 'prompt_studio',
                  icon: Icons.auto_fix_high_outlined,
                  eyebrow: s(context, 'library'),
                  headline: s(context, 'savedCount', {'n': _items.length}),
                  caption: s(context, 'heroCaption'),
                ),
                const SizedBox(height: NexSpacing.md),
                NexSearchField(
                  controller: _search,
                  fieldKey: const ValueKey('studio-search'),
                  hintText: s(context, 'search'),
                  onChanged: (_) {
                    _searchDelay?.cancel();
                    _searchDelay = Timer(const Duration(milliseconds: 160), () {
                      if (mounted) setState(() {});
                    });
                  },
                ),
                const SizedBox(height: NexSpacing.md),
                NexAdaptiveSegments<int>(
                  segments: [
                    for (final (i, key) in [
                      'library',
                      'favorites',
                      'blocks',
                    ].indexed)
                      ButtonSegment(value: i, label: Text(s(context, key))),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (v) => setState(() => _filter = v.first),
                ),
                const SizedBox(height: NexSpacing.md),
                if (visible.isEmpty)
                  NexEmptyState(
                    icon: Icons.edit_note,
                    message: s(context, _items.isEmpty ? 'empty' : 'noMatches'),
                  ),
                for (final entry in visible) _tile(entry),
                if (_filter != 2 && _search.text.isEmpty) ...[
                  const SizedBox(height: NexSpacing.md),
                  NexShelfHeading(
                    icon: Icons.lightbulb_outline,
                    title: s(context, 'starters'),
                  ),
                  Wrap(
                    spacing: NexSpacing.sm,
                    runSpacing: NexSpacing.sm,
                    children: [
                      for (final (label, body) in [
                        ('starterBrief', 'briefBody'),
                        ('starterCode', 'codeBody'),
                        ('starterImage', 'imageBody'),
                      ])
                        ActionChip(
                          label: Text(s(context, label)),
                          avatar: const Icon(Icons.add),
                          onPressed: () => _edit(
                            draftKey:
                                '$body:${NexModuleStrings.persian(context)}',
                            seed: {
                              'title': s(context, label),
                              'body': s(context, body),
                              'block': false,
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
