import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nex_core/nex_core.dart';
import '../tokens/nex_text_direction.dart';
import '../tokens/nex_tokens.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    this.onTap,
    this.previewOverride,
    this.footnote,
  });
  final Note note;
  final VoidCallback? onTap;
  final Widget? previewOverride;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md, vertical: 5),
      child: Semantics(
        button: onTap != null,
        label: _label(),
        excludeSemantics: true,
        child: Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NexColors.cardRadius),
            side: BorderSide(color: theme.colorScheme.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(NexSpacing.cardInset),
              // The card lays itself out in the direction of the note's own
              // text, so a Persian note reads right-to-left even while the
              // interface is in English — icon, body, date and tags together.
              child: NexTextDirection(
                text: note.searchableDerivedText,
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Leading(note: note),
                  const SizedBox(width: NexSpacing.contentGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        previewOverride ?? _Preview(note: note),
                        if (footnote != null) ...[
                          const SizedBox(height: NexSpacing.xs),
                          Text(footnote!, style: theme.textTheme.bodySmall),
                        ],
                        const SizedBox(height: NexSpacing.sm),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: [
                            Text(DateFormat.MMMd().format(note.createdAt.toLocal()), style: theme.textTheme.bodySmall),
                            for (final tag in note.tags) TagChip(tag: tag, compact: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _label() => [
    '${note.type.name} note',
    note.searchableDerivedText ?? '',
    if (note.tags.isNotEmpty)
      'Tags: ${note.tags.map((tag) => tag.name).join(', ')}',
  ].where((value) => value.isNotEmpty).join('. ');
}

class _Preview extends StatelessWidget {
  const _Preview({required this.note});
  final Note note;
  @override
  Widget build(BuildContext context) {
    final text = note.searchableDerivedText ?? note.type.name;
    return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge);
  }
}

class _Leading extends StatelessWidget {
  const _Leading({required this.note});
  final Note note;
  @override
  Widget build(BuildContext context) {
    final uri = note.mediaUri;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (note.type == NoteType.photo && uri != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(uri),
          width: 56,
          height: 56,
          cacheWidth: (56 * ratio).round(),
          cacheHeight: (56 * ratio).round(),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _IconBox(Icons.image_not_supported_outlined),
        ),
      );
    }
    return _IconBox(switch (note.type) {
      NoteType.text => Icons.short_text,
      NoteType.voice => Icons.graphic_eq,
      NoteType.photo => Icons.image_outlined,
      NoteType.file => Icons.insert_drive_file_outlined,
    });
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(icon),
  );
}

class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.tag, this.compact = false, this.onRemove});
  final Tag tag;
  final bool compact;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => InputChip(
    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    label: Text(tag.name),
    avatar: tag.color == null ? null : Semantics(
      label: 'Accent color',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: nexParseTagColor(tag.color),
        ),
      ),
    ),
    onDeleted: onRemove,
  );
}