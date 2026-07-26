import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_services.dart';
import '../platform/polish_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.services});
  final NexServices services;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final query = TextEditingController();
  final tags = <String>{};
  final types = <NoteType>{};
  Timer? debounce;
  DateTimeRange? range;
  List<Note> results = const [];
  Note? nearest;
  bool filtersOpen = false;
  int request = 0;

  late final polish = PolishService(widget.services.repo);

  @override
  void initState() { super.initState(); run(); }

  void schedule() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 150), run);
  }

  void run() {
    final current = ++request;
    final found = widget.services.search.search(SearchFilters(
      query: query.text,
      tagIds: tags.toList(),
      types: types.toList(),
      createdFrom: range?.start,
      createdTo: range?.end.add(const Duration(days: 1)),
    ));
    final close = found.isEmpty && query.text.trim().isNotEmpty
        ? polish.nearestMiss(query.text)
        : null;
    if (!mounted || current != request) return;
    setState(() { results = found; nearest = close; });
  }

  @override
  void dispose() { debounce?.cancel(); query.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allTags = widget.services.tags.listTags();
    final active = tags.length + types.length + (range == null ? 0 : 1);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: query,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.searchHint, border: InputBorder.none, prefixIcon: const Icon(Icons.search)),
          onChanged: (_) => schedule(),
        ),
        actions: [TextButton(
          onPressed: () => setState(() => filtersOpen = !filtersOpen),
          child: Text(active == 0 ? l10n.filters : l10n.filtersCount(active)),
        )],
      ),
      body: Column(children: [
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : NexMotion.standard,
          child: !filtersOpen ? const SizedBox.shrink() : Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final type in NoteType.values) FilterChip(
                label: Text(l10n.noteType(type.name)),
                selected: types.contains(type),
                onSelected: (value) { setState(() => value ? types.add(type) : types.remove(type)); run(); },
              ),
              for (final tag in allTags) FilterChip(
                label: Text(tag.name),
                selected: tags.contains(tag.id),
                onSelected: (value) { setState(() => value ? tags.add(tag.id) : tags.remove(tag.id)); run(); },
              ),
              ActionChip(
                label: Text(range == null ? l10n.date :
                  DateFormat.yMMMd().format(range!.start) + ' – ' + DateFormat.yMMMd().format(range!.end)),
                onPressed: () async {
                  final value = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (value != null) setState(() => range = value);
                  run();
                },
              ),
            ]),
          ),
        ),
        Expanded(child: results.isEmpty
          ? _Zero(query: query.text, nearest: nearest)
          : ListView.builder(
              itemCount: results.length + 1,
              itemBuilder: (context, index) => index == 0
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.resultCount(results.length), style: Theme.of(context).textTheme.bodySmall),
                  )
                : NoteCard(note: results[index - 1]),
            )),
      ]),
    );
  }
}

class _Zero extends StatelessWidget {
  const _Zero({required this.query, required this.nearest});
  final String query;
  final Note? nearest;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (query.trim().isEmpty) return Center(child: Text(l10n.searchStart));
    return Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.nothingMatches(query), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          if (nearest != null) ...[
            Text(l10n.closestThing, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            NoteCard(note: nearest!),
          ] else Text(l10n.nothingClose),
        ]),
      ),
    ));
  }
}