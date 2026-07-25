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

  void _run() {
    setState(() {
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
              decoration: const InputDecoration(
                hintText: 'Search notes…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _run(),
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
                      label: Text(type.wireName),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: NexSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Voice notes: searchable by tag/date only',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final note = _results[index];
                return NoteCard(
                  note: note,
                  onTap: () async {
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => NoteDetailSheet(
                        services: widget.services,
                        noteId: note.id,
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
