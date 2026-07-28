import 'dart:io';
import 'package:flutter/material.dart';
// intl exports a TextDirection that is not dart:ui's, which makes every
// TextDirection here ambiguous. Only DateFormat is wanted from it.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:nex_core/nex_core.dart';
import '../tokens/nex_text_direction.dart';
import '../tokens/nex_tokens.dart';

/// The words a screen reader needs, in the language the user chose.
///
/// This package deliberately carries no localisations of its own — the same
/// reason [TagFilterRow.allLabel] is passed in — but the semantic strings were
/// built into the card in English regardless. A Persian user running TalkBack
/// heard "text note. Tags: کار": the structure in one language, the content in
/// another.
class NexCardStrings {
  const NexCardStrings({
    required this.noteOfType,
    required this.tagList,
    required this.accentColor,
  });

  /// English default, for tests and for anything that has not been localised
  /// yet. The app passes the real thing.
  static const fallback = NexCardStrings(
    noteOfType: _defaultNoteOfType,
    tagList: _defaultTagList,
    accentColor: 'Accent color',
  );

  static String _defaultNoteOfType(String type) => '$type note';
  static String _defaultTagList(String tags) => 'Tags: $tags';

  /// "Voice note", given the note's type name.
  final String Function(String type) noteOfType;

  /// "Tags: work, ideas", given the joined names.
  final String Function(String tags) tagList;

  final String accentColor;
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    this.onTap,
    this.previewOverride,
    this.footnote,
    this.strings = NexCardStrings.fallback,
  });
  final Note note;
  final VoidCallback? onTap;
  final Widget? previewOverride;
  final String? footnote;
  final NexCardStrings strings;

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
          // Not `excludeSemantics`. That collapsed the whole card into one
          // string, so a screen-reader user could not reach the date, an
          // individual tag, or the preview separately — a long undifferentiated
          // announcement with nothing inside it to navigate to.
          explicitChildNodes: true,
          child: Material(
            // The card's own fill, not the page's. They used to be the same
            // colour, which left a 1.2:1 hairline as the only thing marking the
            // boundary of the app's main tap target.
            color: theme.colorScheme.surfaceContainerLowest,
            elevation: 1,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NexRadius.lg),
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
    strings.noteOfType(note.type.name),
    note.searchableDerivedText ?? '',
    if (note.tags.isNotEmpty)
      strings.tagList(note.tags.map((tag) => tag.name).join(', ')),
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
              const SizedBox(width: NexSpacing.sm),
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
        // Concentric with the card: the outer radius less the inset that
        // separates them, rather than an unrelated number.
        borderRadius: BorderRadius.circular(
          NexRadius.inside(NexRadius.lg, NexSpacing.cardInset),
        ),
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
    return _IconBox(nexNoteTypeIcon(note.type.wireName));
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(
          NexRadius.inside(NexRadius.lg, NexSpacing.cardInset),
        ),
        // A deliberate 56px element used to sit at 1.10:1 against the card,
        // which rendered it as nothing but a floating glyph. The fill carries a
        // real tonal step now, and the ring carries the boundary.
        border: Border.all(color: scheme.outline),
      ),
      child: Icon(icon, color: scheme.onSurfaceVariant),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.tag,
    this.compact = false,
    this.onRemove,
    this.strings = NexCardStrings.fallback,
  });
  final Tag tag;
  final bool compact;
  final VoidCallback? onRemove;
  final NexCardStrings strings;
  @override
  Widget build(BuildContext context) => InputChip(
    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    // A chip's default tap target is 48px tall — half again the chip itself,
    // and on a card it is decoration rather than a control, so that padding
    // was pure card height. A removable chip *is* a control and keeps it.
    materialTapTargetSize:
        compact && onRemove == null ? MaterialTapTargetSize.shrinkWrap : null,
    label: Text(tag.name),
    avatar: tag.color == null ? null : Semantics(
      label: strings.accentColor,
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