import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import '../tokens/nex_relative_time.dart';
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
    this.relativeTime = _defaultRelativeTime,
    this.dueLabel,
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

  /// Compact English shorthand — "now", "5m", "8h", "1d", "2w", "1mo", "1y".
  /// The app supplies Persian's own, more legible phrasing for the same
  /// buckets.
  static String _defaultRelativeTime(NexRelativeTime time) =>
      switch (time.unit) {
        NexRelativeUnit.now => 'now',
        NexRelativeUnit.minutes => '${time.count}m',
        NexRelativeUnit.hours => '${time.count}h',
        NexRelativeUnit.days => '${time.count}d',
        NexRelativeUnit.weeks => '${time.count}w',
        NexRelativeUnit.months => '${time.count}mo',
        NexRelativeUnit.years => '${time.count}y',
      };

  /// "Voice note", given the note's type name.
  final String Function(String type) noteOfType;

  /// "Tags: work, ideas", given the joined names.
  final String Function(String tags) tagList;

  final String accentColor;

  /// "8h", "2w" and so on — see [NexRelativeTime].
  final String Function(NexRelativeTime time) relativeTime;

  /// "in 2 hours", "Overdue" — how long until a note's reminder.
  ///
  /// Null leaves the card showing the bell alone, which is what it did before
  /// and is still the right answer for a caller that has no localisation to
  /// hand. A bell with no time beside it says a reminder exists and nothing
  /// else, which was the report this parameter exists to answer.
  final String Function(DateTime due)? dueLabel;
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    this.onTap,
    this.previewOverride,
    this.strings = NexCardStrings.fallback,
  });
  final Note note;
  final VoidCallback? onTap;
  final Widget? previewOverride;
  final NexCardStrings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: nexCardInsets,
      child: SizedBox(
        // Every card, the same height. See [nexCardHeightFor] — which is
        // [nexCardHeight] at the default text size, and only grows if someone
        // has turned the text up past what the glyph's 48 can hold.
        height: nexCardHeightFor(context),
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
    required this.strings,
  });

  final Note note;
  final VoidCallback? onTap;
  final Widget? previewOverride;
  final NexCardStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      // The card's own fill, not the page's. They used to be the same
      // colour, which left a 1.2:1 hairline as the only thing marking the
      // boundary of the app's main tap target.
      color: theme.colorScheme.surfaceContainerLowest,
      // Flat. No outline and no shadow: the boundary is the tonal step
      // between the card's fill and the page's, and nothing else.
      //
      // The shadow was doing the outline's share of the work as well as its
      // own, and a screen of it read as busy — dozens of soft edges stacked
      // down a list, none of them carrying information. Losing it costs
      // something real in the dark theme, where the step between page and
      // card was four values of lightness; `bgCardDark` was opened up to pay
      // for that rather than quietly leaving the cards invisible.
      elevation: 0,
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
              _LeadingWithPin(note: note, strings: strings),
              const SizedBox(width: NexSpacing.contentGap),
              // Beside the glyph, not under the preview. Stacked, it was the
              // one line that did not fit once the preview took two — and
              // making the card taller to hold it spent height on the least
              // important thing on the card. Here it costs nothing vertically,
              // and it doubles as the gap that keeps the text off the glyph.
              Text(
                strings.relativeTime(nexRelativeTimeOf(note.updatedAt)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              // A note that asked to come back says so on the card. Without
              // it a reminder is invisible until it fires, which means the
              // only way to check one was set is to open the note.
              if (note.dueAt case final due?) ...[
                const SizedBox(width: NexSpacing.xs),
                _DueChip(
                  due: due,
                  label: strings.dueLabel?.call(due),
                  // A lapsed reminder is not an alarm any more, so it stops
                  // asking for attention in the accent colour.
                  upcoming: due.isAfter(DateTime.now().toUtc()),
                ),
              ],
              const SizedBox(width: NexSpacing.contentGap),
              Expanded(child: previewOverride ?? _Preview(note: note)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bell on a card, and when it will ring.
///
/// It was the bell on its own, which said a reminder existed and nothing
/// about it — so the only thing anyone could do with a reminder they could not
/// read was delete it. Every app that sets reminders on a list row puts the
/// time on the row.
///
/// The text is optional and the bell is not: a caller with no localisation
/// still gets the mark it always had.
class _DueChip extends StatelessWidget {
  const _DueChip({
    required this.due,
    required this.label,
    required this.upcoming,
  });

  final DateTime due;
  final String? label;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = upcoming
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final text = label;
    if (text == null) {
      return Icon(
        Icons.notifications_active_outlined,
        size: 14,
        color: color,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NexRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_outlined,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Up to 4 tag-colour dots, one per corner of the leading icon box.
///
/// On the icon rather than in a column beside it: a column cost the card no
/// height, but a photo note's thumbnail already fills that column's width
/// with the photo itself, so the dots had nowhere consistent to sit once a
/// card's leading square stopped always being a bare glyph. A dot pinned to
/// the icon's own corner reads as a property of that note's icon at a
/// glance, the way an app badge sits on a home-screen icon, without a
/// second column competing with the preview text for width.
///
/// Corners fill top-right, bottom-left, top-left, bottom-right in that
/// order — RTL-aware (top-end, bottom-start, top-start, bottom-end) — so a
/// fourth tag's dot lands under the pin badge on a pinned note rather than
/// swapping position with it.
///
/// A tag with no colour still gets a mark, drawn as an outline, so "this note
/// is tagged" never depends on the user having picked a colour. Display-only:
/// nothing here reacts to a tap, since a dot this small identifies a tag by
/// colour, not by picking it.
class _CornerTagDots extends StatelessWidget {
  const _CornerTagDots({required this.tags, required this.strings});

  static const _max = 4;
  static const _size = 10.0;

  static const _corners = [
    _DotCorner.topEnd,
    _DotCorner.bottomStart,
    _DotCorner.topStart,
    _DotCorner.bottomEnd,
  ];

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
      child: SizedBox(
        width: nexCardLeadingSize,
        height: nexCardLeadingSize,
        child: Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              _positioned(
                _corners[i],
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _positioned(_DotCorner corner, Widget dot) => switch (corner) {
    _DotCorner.topEnd => PositionedDirectional(top: 0, end: 0, child: dot),
    _DotCorner.bottomStart => PositionedDirectional(
      bottom: 0,
      start: 0,
      child: dot,
    ),
    _DotCorner.topStart => PositionedDirectional(top: 0, start: 0, child: dot),
    _DotCorner.bottomEnd => PositionedDirectional(
      bottom: 0,
      end: 0,
      child: dot,
    ),
  };
}

enum _DotCorner { topEnd, bottomStart, topStart, bottomEnd }

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
    // A checklist and a link both have a shape worth showing at a glance, and
    // both fit the same two lines every other card gets. Neither is
    // interactive here: the card's own tap opens the note, and a checkbox
    // inside a tappable card is a target inside a target.
    if (note.type == NoteType.checklist && note.checklistItems.isNotEmpty) {
      return _ChecklistPreview(items: note.checklistItems);
    }
    if (note.type == NoteType.link) return _LinkPreview(note: note);

    final text = note.displayText ?? note.type.name;
    final direction = nexDirectionOf(text);
    return SizedBox(
      // Full width, so a short right-to-left line reaches the right edge
      // instead of hugging the left one it happens to start at.
      width: double.infinity,
      child: Text(
        text,
        // Two lines — see [nexCardPreviewLines], which the card's fixed
        // height is derived from. One line was enough to tell cards apart
        // and not enough to tell you what a note said: a captured thought is
        // usually a sentence, and a sentence is usually wider than a phone.
        maxLines: nexCardPreviewLines,
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

/// The first two items of a checklist, ticked or not, plus what is left over.
///
/// Two, because that is what the card has room for — and the two that matter
/// are the ones still to do, so unticked items come first regardless of where
/// they sit in the list. A card showing "milk, bread" you have already bought
/// is a card telling you nothing.
class _ChecklistPreview extends StatelessWidget {
  const _ChecklistPreview({required this.items});

  final List<ChecklistItem> items;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...items.where((item) => !item.done),
      ...items.where((item) => item.done),
    ];
    final shown = ordered.take(nexCardPreviewLines).toList();
    final remaining = ordered.length - shown.length;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in shown)
            _ChecklistLine(
              item: item,
              // The last visible line carries the overflow count, so the
              // card never grows a third row to say "+3 more".
              trailing: item == shown.last && remaining > 0
                  ? '+$remaining'
                  : null,
            ),
          if (shown.length < nexCardPreviewLines)
            // Holds the card's height steady when a list has one item, the
            // same way a one-line text note reserves its second line.
            SizedBox(height: 24.0 * (nexCardPreviewLines - shown.length)),
        ],
      ),
    );
  }
}

class _ChecklistLine extends StatelessWidget {
  const _ChecklistLine({required this.item, this.trailing});

  final ChecklistItem item;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final direction = nexDirectionOf(item.text);
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          Icon(
            item.done
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            size: 16,
            color: item.done ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              item.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: direction,
              textAlign: direction == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.start,
              style: theme.textTheme.bodyMedium?.copyWith(
                // Struck through and dimmed rather than hidden: what you have
                // already done is part of what the list says.
                decoration: item.done ? TextDecoration.lineThrough : null,
                color: item.done ? scheme.onSurfaceVariant : null,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: NexSpacing.sm),
            Text(
              trailing!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A link note: what the page is called, and which site it is on.
///
/// The host on its own line is the part that stops a list of bookmarks from
/// being unreadable — titles repeat across a site, domains do not.
class _LinkPreview extends StatelessWidget {
  const _LinkPreview({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = urlHost(note.linkUrl);
    // Before the page has been read, the URL is the only thing there is to
    // show — which is honest, and better than an empty card that looks broken.
    final headline = note.displayText ?? note.linkUrl ?? '';
    final direction = nexDirectionOf(headline);
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            child: Text(
              headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: direction,
              textAlign: direction == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.start,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Icon(
                  Icons.public,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: NexSpacing.xs),
                Expanded(
                  child: Text(
                    host ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        // Matches _IconBox's own rounding — see NexRadius.cardLeading — so a
        // photo note's thumbnail and every other type's icon box read as the
        // same shape.
        borderRadius: BorderRadius.circular(NexRadius.cardLeading),
        child: Image.file(
          File(uri),
          width: nexCardLeadingSize,
          height: nexCardLeadingSize,
          cacheWidth: (nexCardLeadingSize * ratio).round(),
          cacheHeight: (nexCardLeadingSize * ratio).round(),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
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
  const _LeadingWithPin({required this.note, required this.strings});

  final Note note;
  final NexCardStrings strings;

  static const _size = 20.0;

  @override
  Widget build(BuildContext context) {
    final leading = _Leading(note: note);
    final hasTags = note.tags.isNotEmpty;
    if (note.pinnedAt == null && !hasTags) return leading;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      // The badge sits half off the square's corner. Nothing is clipped: it
      // lands well inside the card, which is what does the clipping here.
      clipBehavior: Clip.none,
      children: [
        leading,
        if (hasTags) _CornerTagDots(tags: note.tags, strings: strings),
        if (note.pinnedAt != null)
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
        borderRadius: BorderRadius.circular(NexRadius.cardLeading),
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
