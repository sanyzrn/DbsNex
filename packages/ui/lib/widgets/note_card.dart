import 'dart:io';
import 'package:flutter/material.dart';
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
          child: _CardBody(
            note: note,
            onTap: onTap,
            previewOverride: previewOverride,
            footnote: footnote,
            strings: strings,
          ),
        ),
      ),
    );
  }

  /// The card's own announcement: what kind of note, and what it says.
  ///
  /// The tags are deliberately not here. They are announced by the dots, which
  /// is the node a screen-reader user can actually navigate to — repeating them
  /// on the parent would read the tag list twice on the way past.
  String _label() => [
    strings.noteOfType(note.type.name),
    note.displayText ?? '',
  ].where((value) => value.isNotEmpty).join('. ');
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.note,
    required this.onTap,
    required this.previewOverride,
    required this.footnote,
    required this.strings,
  });

  final Note note;
  final VoidCallback? onTap;
  final Widget? previewOverride;
  final String? footnote;
  final NexCardStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      // The card's own fill, not the page's. They used to be the same
      // colour, which left a 1.2:1 hairline as the only thing marking the
      // boundary of the app's main tap target.
      color: theme.colorScheme.surfaceContainerLowest,
      // No outline: the boundary is carried by the tonal step between the
      // card's fill and the page's, plus the shadow. The shadow is a
      // little deeper than it was because it is now doing the outline's
      // share of the work as well as its own.
      elevation: 2,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.cardInset),
          child: Row(
            children: [
              _LeadingWithPin(note: note),
              const SizedBox(width: NexSpacing.contentGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    previewOverride ?? _Preview(note: note),
                    if (footnote != null) ...[
                      const SizedBox(height: NexSpacing.xs),
                      Text(
                        footnote!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              // Colours, not names. A tag's name is already in its own
              // words inside the note; on the card it was competing with
              // the note's first line for the same glance, and three of
              // them filled the row. The dot is the whole of what a
              // timeline needs: which tags, at a glance, without reading.
              if (note.tags.isNotEmpty) ...[
                const SizedBox(width: NexSpacing.sm),
                _TagDots(tags: note.tags, strings: strings),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tag's colour, stacked down the card's trailing edge.
///
/// Vertical rather than a row under the text: it costs the card no height at
/// all, which is the point — the date and the tag chips were most of why a card
/// was 120px tall. Capped at four, because past that they stop being
/// distinguishable and start being a texture.
///
/// A tag with no colour still gets a mark, drawn as an outline, so "this note
/// is tagged" never depends on the user having picked a colour.
class _TagDots extends StatelessWidget {
  const _TagDots({required this.tags, required this.strings});

  static const _max = 4;
  static const _size = 8.0;

  final List<Tag> tags;
  final NexCardStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = tags.take(_max).toList();
    return Semantics(
      // A node of its own: the card sets `explicitChildNodes`, so a label
      // without a container of its own merges into the parent and stops being
      // something a screen reader can navigate to.
      container: true,
      label: strings.tagList(tags.map((tag) => tag.name).join(', ')),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: NexSpacing.xs + 2),
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: nexParseTagColor(shown[i].color),
                border: shown[i].color == null
                    ? Border.all(color: scheme.outline, width: 1.5)
                    : null,
              ),
            ),
          ],
        ],
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
    final text = note.displayText ?? note.type.name;
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
          width: nexCardLeadingSize,
          height: nexCardLeadingSize,
          cacheWidth: (nexCardLeadingSize * ratio).round(),
          cacheHeight: (nexCardLeadingSize * ratio).round(),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const _IconBox(Icons.image_not_supported_outlined),
        ),
      );
    }
    return _IconBox(nexNoteTypeIcon(note.type.wireName));
  }
}

/// The leading glyph, with a pin badge on it when the note is held in place.
///
/// A glance is the whole point: which one card, among many, is pinned. That
/// used to be a bare 14px glyph floated into the card's top corner by a Stack
/// — outside the card's own padding, crowding its corner radius, attached to
/// nothing. A badge on the leading square is the same information sitting on
/// an object that is already there, which is what makes it read as part of the
/// card rather than as something dropped on top of it.
class _LeadingWithPin extends StatelessWidget {
  const _LeadingWithPin({required this.note});

  final Note note;

  static const _size = 20.0;

  @override
  Widget build(BuildContext context) {
    final leading = _Leading(note: note);
    if (note.pinnedAt == null) return leading;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      // The badge sits half off the square's corner. Nothing is clipped: it
      // lands well inside the card, which is what does the clipping here.
      clipBehavior: Clip.none,
      children: [
        leading,
        PositionedDirectional(
          bottom: -NexSpacing.xs,
          end: -NexSpacing.xs,
          child: Container(
            width: _size,
            height: _size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // The card's own fill, so the badge reads as lifted off the
              // square rather than painted onto it.
              color: scheme.surfaceContainerLowest,
              border: Border.all(color: scheme.outline),
            ),
            child: Icon(
              Icons.push_pin,
              size: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: nexCardLeadingSize,
      height: nexCardLeadingSize,
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
    materialTapTargetSize: compact && onRemove == null
        ? MaterialTapTargetSize.shrinkWrap
        : null,
    label: Text(tag.name),
    avatar: tag.color == null
        ? null
        : Semantics(
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
