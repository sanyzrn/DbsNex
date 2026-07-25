import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../platform/nex_services.dart';

class NoteDetailSheet extends StatefulWidget {
  const NoteDetailSheet({
    super.key,
    required this.services,
    required this.noteId,
    this.focusAddTag = false,
  });

  final NexServices services;
  final String noteId;
  final bool focusAddTag;

  @override
  State<NoteDetailSheet> createState() => _NoteDetailSheetState();
}

class _NoteDetailSheetState extends State<NoteDetailSheet> {
  Note? _note;
  List<TagSuggestion> _suggestions = const [];
  List<SemanticHit> _related = const [];
  String? _color;

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.focusAddTag) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addTag());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAi());
  }

  void _reload() {
    setState(() => _note = widget.services.repo.getById(widget.noteId));
  }

  Future<void> _loadAi() async {
    final suggestions =
        await widget.services.enrichment.suggestTags(widget.noteId);
    final related =
        await widget.services.enrichment.relatedNotes(widget.noteId);
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _related = related;
    });
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    _color = null;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Add tag'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Tag name'),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Wrap(
                    spacing: NexSpacing.xs,
                    children: [
                      for (final suggestion in suggestedStarterTags)
                        ActionChip(
                          label: Text(suggestion),
                          onPressed: () => Navigator.pop(ctx, suggestion),
                        ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Wrap(
                    spacing: NexSpacing.xs,
                    children: [
                      for (final hex in tagAccentPalette)
                        GestureDetector(
                          onTap: () => setLocal(() => _color = hex),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(hex.substring(1), radix: 16) +
                                    0xFF000000,
                              ),
                              shape: BoxShape.circle,
                              border: _color == hex
                                  ? Border.all(
                                      color: Theme.of(ctx).colorScheme.primary,
                                      width: 2,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
    if (name != null && name.isNotEmpty) {
      widget.services.tags.addTag(
        noteId: widget.noteId,
        name: name,
        color: _color,
      );
      _reload();
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    if (note == null) {
      return const Padding(
        padding: EdgeInsets.all(NexSpacing.lg),
        child: Text('Note not found'),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        left: NexSpacing.md,
        right: NexSpacing.md,
        top: NexSpacing.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NexSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.type.wireName.toUpperCase(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: NexSpacing.sm),
            if (note.type == NoteType.text)
              Text(
                note.content ?? '',
                style: Theme.of(context).textTheme.bodyLarge,
              )
            else if (note.type == NoteType.voice) ...[
              Text(
                'Voice · ${((note.durationMs ?? 0) / 1000).ceil()}s',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (note.transcriptText != null) ...[
                const SizedBox(height: NexSpacing.sm),
                Text(
                  'Transcript',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(note.transcriptText!),
              ] else
                Text(
                  'Searchable by tag/date only',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ] else if (note.type == NoteType.photo) ...[
              Text('Photo', style: Theme.of(context).textTheme.bodyLarge),
              if (note.ocrText != null) ...[
                const SizedBox(height: NexSpacing.sm),
                Text('OCR', style: Theme.of(context).textTheme.bodySmall),
                Text(note.ocrText!),
              ],
            ] else
              Text('File', style: Theme.of(context).textTheme.bodyLarge),
            if (note.summaryText != null) ...[
              const SizedBox(height: NexSpacing.md),
              Text('Summary', style: Theme.of(context).textTheme.bodySmall),
              Text(note.summaryText!),
            ],
            const SizedBox(height: NexSpacing.md),
            Wrap(
              spacing: NexSpacing.xs,
              children: [
                for (final tag in note.tags)
                  TagChip(
                    tag: tag,
                    onRemove: () {
                      widget.services.tags.removeTag(
                        noteId: note.id,
                        tagId: tag.id,
                      );
                      _reload();
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Tag'),
                  onPressed: _addTag,
                ),
              ],
            ),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Suggested tags (dismissible)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _suggestions = const []),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
              Wrap(
                spacing: NexSpacing.xs,
                children: [
                  for (final s in _suggestions)
                    ActionChip(
                      label: Text(s.name),
                      onPressed: () {
                        widget.services.tags.addTag(
                          noteId: note.id,
                          name: s.name,
                        );
                        setState(() {
                          _suggestions =
                              _suggestions.where((x) => x.name != s.name).toList();
                        });
                        _reload();
                      },
                    ),
                ],
              ),
            ],
            if (_related.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.md),
              Text(
                'Related notes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final hit in _related)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    widget.services.repo.getById(hit.noteId)?.content ??
                        hit.noteId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('similarity ${hit.score.toStringAsFixed(2)}'),
                ),
            ],
            const SizedBox(height: NexSpacing.md),
            TextButton(
              onPressed: () async {
                await widget.services.enrichment.summarizeOnDemand(note.id);
                _reload();
              },
              child: const Text('Summarize'),
            ),
            TextButton(
              onPressed: () {
                widget.services.repo.softDelete(note.id);
                Navigator.pop(context);
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
