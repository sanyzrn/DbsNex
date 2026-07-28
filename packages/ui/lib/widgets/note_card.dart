import 'dart:io';
import 'package:flutter/material.dart';
// intl exports a TextDirection that is not dart:ui's, which makes every
// TextDirection here ambiguous. Only DateFormat is wanted from it.
import 'package:intl/intl.dart' hide TextDirection;
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
      padding: nexCardInsets,
      child: SizedBox(
        // Every card, the same height. See [nexCardHeight].
        height: nexCardHeight,
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Leading(note: note),
                    const SizedBox(width: NexSpacing.contentGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The text takes whatever the metadata row leaves,
                          // and sits at the top of it — so a one-line note and
                          // a two-line note both start on the same baseline
                          // instead of floating in a differently sized card.
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.topStart,
                              child: previewOverride ?? _Preview(note: note),
                            ),
                          ),
                          if (footnote != null)
                            Text(
                              footnote!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          _Meta(note: note),
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

/// The date and the tags, on exactly one line.
///
/// A [Wrap] here was what made cards different heights: a note with three tags
/// pushed them onto a second run and grew the card by 30px. This keeps the row
/// to its one line and lets a tag that does not fit run off the edge, which
/// reads as "there are more" — the card is a preview, and the note's own sheet
/// is where every tag is listed.
class _Meta extends StatelessWidget {
  const _Meta({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: nexCardMetaHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Not scrollable: this is a clip, not a control. NeverScrollable also
        // keeps it out of the gesture arena, so it cannot compete with the
        // card's own swipe.
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat.MMMd().format(note.createdAt.toLocal()),
              style: theme.textTheme.bodySmall,
            ),
            for (final tag in note.tags) ...[
              const SizedBox(width: 6),
              TagChip(tag: tag, compact: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// The note's own words, laid out in the note's own direction.
///
/// Only the text turns. Wrapping the whole card in a [Directionality] also
/// moved the type icon, the date and the tag chips to the other side, so a
/// Persian note came out mirrored against every card around it — the text was
/// right but the card was wrong. Direction here belongs to the paragraph, and
/// the card keeps the layout the interface language gives it.
class _Preview extends StatelessWidget {
  const _Preview({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final text = note.searchableDerivedText ?? note.type.name;
    final direction = nexDirectionOf(text);
    return SizedBox(
      // Full width, so a short right-to-left line reaches the right edge
      // instead of hugging the left one it happens to start at.
      width: double.infinity,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textDirection: direction,
        textAlign: direction == TextDirection.rtl
            ? TextAlign.right
            : TextAlign.start,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
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
    // A chip's default tap target is 48px tall — half again the chip itself,
    // and on a card it is decoration rather than a control, so that padding
    // was pure card height.
    materialTapTargetSize:
        compact ? MaterialTapTargetSize.shrinkWrap : null,
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