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
  final _selectedTags = <String>{};
  final _selectedTypes = <NoteType>{};
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
          tagIds: _selectedTags.toList(),
          createdFrom: _from,
          createdTo: _to,
          types: _selectedTypes.toList(),
        ),
      );
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedTags.clear();
      _selectedTypes.clear();
      _from = null;
      _to = null;
      _query.clear();
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final allTags = widget.services.tags.listTags();
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _semantic ? 'Search by meaning…' : 'Search notes…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _run(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Semantic (meaning)'),
                selected: _semantic,
                onSelected: (v) {
                  setState(() => _semantic = v);
                  _run();
                },
              ),
            ),
          ),
          if (_semantic)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: NexSpacing.md,
                vertical: NexSpacing.xs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Semantic results — distinct from exact keyword matches',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
            child: Row(
              children: [
                for (final type in NoteType.values)
                  Padding(
                    padding: const EdgeInsets.only(right: NexSpacing.xs),
                    child: FilterChip(
                      label: Text(_typeLabel(type)),
                      selected: _selectedTypes.contains(type),
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedTypes.add(type);
                          } else {
                            _selectedTypes.remove(type);
                          }
                        });
                        _run();
                      },
                    ),
                  ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setState(() {
                        _from = picked.start.toUtc();
                        _to = picked.end
                            .add(const Duration(days: 1))
                            .toUtc();
                      });
                      _run();
                    }
                  },
                  child: Text(
                    _from == null
                        ? 'Date'
                        : '${_from!.toLocal().toString().split(' ').first} → ${_to!.toLocal().toString().split(' ').first}',
                  ),
                ),
                TextButton(onPressed: _clearFilters, child: const Text('Clear')),
              ],
            ),
          ),
          if (allTags.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: NexSpacing.md,
                vertical: NexSpacing.xs,
              ),
              child: Row(
                children: [
                  for (final tag in allTags)
                    Padding(
                      padding: const EdgeInsets.only(right: NexSpacing.xs),
                      child: FilterChip(
                        label: Text(tag.name),
                        selected: _selectedTags.contains(tag.id),
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedTags.add(tag.id);
                            } else {
                              _selectedTags.remove(tag.id);
                            }
                          });
                          _run();
                        },
                      ),
                    ),
                ],
              ),
            ),
          if (!_semantic)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: NexSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Keyword search includes transcripts and OCR when available',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final note = _results[index];
                final score = _semanticScores[note.id];
                return NoteCard(
                  note: note,
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

  static String _typeLabel(NoteType type) => switch (type) {
        NoteType.text => 'Text',
        NoteType.voice => 'Voice',
        NoteType.photo => 'Photo',
        NoteType.file => 'File',
      };
}
