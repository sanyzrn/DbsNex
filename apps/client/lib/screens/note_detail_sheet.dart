import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../platform/nex_services.dart';

class NoteDetailSheet extends StatefulWidget {
  const NoteDetailSheet({
    super.key,
    required this.services,
    required this.noteId,
  });

  final NexServices services;
  final String noteId;

  @override
  State<NoteDetailSheet> createState() => _NoteDetailSheetState();
}

class _NoteDetailSheetState extends State<NoteDetailSheet> {
  Note? _note;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _note = widget.services.repo.getById(widget.noteId));
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    String? color;
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
                          onTap: () => setLocal(() => color = hex),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(hex.substring(1), radix: 16) +
                                    0xFF000000,
                              ),
                              shape: BoxShape.circle,
                              border: color == hex
                                  ? Border.all(width: 2)
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
    // Capture color from dialog local state: re-prompt is avoided by reading
    // the last selected color via a closure — store on the State.
    if (name != null && name.isNotEmpty) {
      widget.services.tags.addTag(
        noteId: widget.noteId,
        name: name,
        color: color,
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
            else if (note.type == NoteType.voice)
              Text(
                'Voice · ${((note.durationMs ?? 0) / 1000).ceil()}s\nSearchable by tag/date only',
                style: Theme.of(context).textTheme.bodyLarge,
              )
            else
              Text('Photo', style: Theme.of(context).textTheme.bodyLarge),
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
            const SizedBox(height: NexSpacing.lg),
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
