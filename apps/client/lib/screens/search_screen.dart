import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../platform/nex_services.dart';
import 'note_detail_sheet.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.services});

  final NexServices services;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  String? _selectedTagId;
  DateTime? _from;
  DateTime? _to;
  List<Note> _results = const [];
  Map<String, double> _semanticScores = const {};
  bool _semantic = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_semantic) {
      final hits = await widget.services.enrichment.semanticSearch(_query.text);
      if (!mounted) return;
      setState(() {
        _semanticScores = {for (final h in hits) h.noteId: h.score};
        _results = [
          for (final h in hits)
            if (widget.services.repo.getById(h.noteId) case final note?) note,
        ];
      });
      return;
    }
    setState(() {
      _semanticScores = const {};
      _results = widget.services.search.search(
        SearchFilters(
          query: _query.text,
          tagIds: _selectedTagId == null ? const [] : [_selectedTagId!],
          createdFrom: _from,
          createdTo: _to,
        ),
      );
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _from = picked.start.toUtc();
        _to = picked.end.add(const Duration(days: 1)).toUtc();
      });
      _run();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allTags = widget.services.tags.listTags();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.md,
              NexSpacing.sm,
              NexSpacing.md,
              0,
            ),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _semantic ? 'Search by meaning…' : 'Search notes…',
                prefixIcon: Icon(
                  Icons.search,
                  color: theme.colorScheme.secondary,
                ),
              ),
              onChanged: (_) => _run(),
            ),
          ),
          TagFilterRow(
            tags: allTags,
            selectedTagId: _selectedTagId,
            onSelected: (id) {
              setState(() => _selectedTagId = id);
              _run();
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: NexSpacing.sm),
                  child: _FilterActionPill(
                    label: _from == null ? 'Date' : 'Date ✓',
                    selected: _from != null,
                    onTap: _pickDate,
                  ),
                ),
                _FilterActionPill(
                  label: 'Semantic',
                  selected: _semantic,
                  onTap: () {
                    setState(() => _semantic = !_semantic);
                    _run();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.md + 4,
              0,
              NexSpacing.md,
              NexSpacing.sm,
            ),
            child: Text(
              _semantic
                  ? '${_results.length} semantic results'
                  : '${_results.length} results',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: NexSpacing.xl),
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final note = _results[index];
                final score = _semanticScores[note.id];
                return NoteCard(
                  note: note,
                  padded: true,
                  footnote: score == null
                      ? null
                      : 'Semantic · ${score.toStringAsFixed(2)}',
                  onTap: () async {
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      useSafeArea: true,
                      builder: (_) => SizedBox(
                        width: double.infinity,
                        child: NoteDetailSheet(
                          services: widget.services,
                          noteId: note.id,
                        ),
                      ),
                    );
                    _run();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterActionPill extends StatelessWidget {
  const _FilterActionPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg =
        selected ? theme.colorScheme.onSurface : theme.colorScheme.surface;
    final fg =
        selected ? theme.colorScheme.surface : theme.colorScheme.onSurface;
    return Material(
      color: bg,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? bg : theme.colorScheme.outline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
