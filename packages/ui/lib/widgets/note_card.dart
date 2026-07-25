import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../tokens/nex_tokens.dart';

/// Timeline card (05-design.md components).
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    this.onTap,
  });

  final Note note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.md,
          vertical: NexSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _preview(theme),
            const SizedBox(height: NexSpacing.xs),
            Row(
              children: [
                Text(
                  _relativeTime(note.createdAt),
                  style: theme.textTheme.bodySmall,
                ),
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: Wrap(
                      spacing: NexSpacing.xs,
                      runSpacing: NexSpacing.xs,
                      children: note.tags.map((t) => TagChip(tag: t)).toList(),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: NexSpacing.sm),
            Divider(height: 1, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }

  Widget _preview(ThemeData theme) {
    switch (note.type) {
      case NoteType.text:
        return Text(
          note.content ?? '',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
          textDirection: _detectDirection(note.content ?? ''),
        );
      case NoteType.voice:
        final secs = ((note.durationMs ?? 0) / 1000).ceil();
        return Row(
          children: [
            Icon(Icons.graphic_eq, size: 20, color: theme.colorScheme.secondary),
            const SizedBox(width: NexSpacing.sm),
            Text('Voice · ${secs}s', style: theme.textTheme.bodyLarge),
            const SizedBox(width: NexSpacing.sm),
            Text(
              'Searchable by tag/date only',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      case NoteType.photo:
        return Row(
          children: [
            Icon(Icons.image_outlined, size: 20, color: theme.colorScheme.secondary),
            const SizedBox(width: NexSpacing.sm),
            Text('Photo', style: theme.textTheme.bodyLarge),
          ],
        );
    }
  }

  static TextDirection _detectDirection(String text) {
    for (final code in text.runes) {
      if (code >= 0x0600 && code <= 0x06FF) return TextDirection.rtl;
    }
    return TextDirection.ltr;
  }

  static String _relativeTime(DateTime at) {
    final diff = DateTime.now().toUtc().difference(at.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }
}

class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.tag,
    this.onRemove,
  });

  final Tag tag;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = tag.color != null
        ? Color(int.parse(tag.color!.substring(1), radix: 16) + 0xFF000000)
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? NexColors.bgElevatedLight
            : NexColors.bgElevatedDark,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accent != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(tag.name, style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
          )),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 14),
            ),
          ],
        ],
      ),
    );
  }
}
