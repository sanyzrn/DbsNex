import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import '../tokens/nex_appearance.dart';
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
    this.tagName,
    this.durationLabel,
    this.attachedShort = _defaultAttachedShort,
    this.attachedLabel = _defaultAttachedLabel,
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
  static String _defaultAttachedShort(int count) => '+$count';
  static String _defaultAttachedLabel(int count) =>
      count == 1 ? '1 more file' : '$count more files';

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
  final String Function(Tag)? tagName;
  final String Function(int milliseconds)? durationLabel;

  /// "+3" — the mark on a card whose note carries files after its own, in
  /// the locale's digits.
  final String Function(int count) attachedShort;

  /// "3 more files" — what that mark says to a screen reader.
  final String Function(int count) attachedLabel;

  /// "8h", "2w" and so on — see [NexRelativeTime].
  final String Function(NexRelativeTime time) relativeTime;

  /// "in 2 hours", "Overdue", "Every day" — what a note's reminder says.
  ///
  /// Takes the repeat as well as the time because the two ask for different
  /// sentences: a one-off counts down to a moment, and a repeating one has no
  /// moment to count down to — its stored time is when the series started,
  /// which is in the past for every repeat that has fired even once.
  ///
  /// Null leaves the card showing the bell alone, which is what it did before
  /// and is still the right answer for a caller that has no localisation to
  /// hand. A bell with no time beside it says a reminder exists and nothing
  /// else, which was the report this parameter exists to answer.
  final String Function(DateTime due, NoteRepeat repeat)? dueLabel;
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    this.onTap,
    this.previewOverride,
    this.strings = NexCardStrings.fallback,
    this.showDue = true,
    this.expanded = false,
    this.selected,
    this.threadAbove = false,
    this.threadBelow = false,
  });
  final Note note;
  final VoidCallback? onTap;
  final Widget? previewOverride;
  final NexCardStrings strings;

  /// Whether this card shows all of its note rather than the first two lines.
  ///
  /// Per note, and off by default. The reason to want one is that *this*
  /// checklist has to stay in view — not that every card should be tall. A
  /// list where every card is as tall as its contents is a list you have to
  /// scroll to compare two things in, which is the ragged layout the fixed
  /// height was introduced to fix.
  final bool expanded;

  /// Whether a reminder on this note still has anything to say.
  ///
  /// A reminder that is still ahead does: "in 3h" at a glance is what the
  /// chip is for. One that has already rung has been delivered once as a
  /// notification and read once here, and after that it is a permanent
  /// "Overdue" badge on a note nobody is late for — so the caller, which is
  /// the only thing that knows whether it has been seen, can turn it off.
  final bool showDue;

  /// Whether this card is picked, while several are being picked at once.
  ///
  /// Null when nothing is being picked — the ordinary card. False draws an
  /// empty ring on the card's icon, so every card on screen says it can be
  /// picked; true fills the icon with a tick and edges the card in the
  /// accent.
  final bool? selected;

  /// Whether a thread runs from this card's leading square to the card
  /// above it, and to the one below.
  ///
  /// The timeline sets these for neighbours under the same day, so each day
  /// reads as one strand — the notes of a morning joined the way the app's
  /// mark joins the pieces it catches — rather than as a pile of separate
  /// boxes. Drawn in the gutter between cards only, never across one.
  final bool threadAbove;
  final bool threadBelow;

  @override
  Widget build(BuildContext context) {
    final insets = nexCardInsetsFor(context);
    final card = _card(context, insets);
    if (!threadAbove && !threadBelow) return card;
    final density = NexCardDensity.of(context);
    return CustomPaint(
      painter: _ThreadPainter(
        above: threadAbove,
        below: threadBelow,
        insets: insets,
        // The middle of the leading square.
        offset: density.inset + density.leading / 2,
        direction: Directionality.of(context),
        color: nexNoteTypeTint(
          note.type.wireName,
          Theme.of(context).colorScheme,
        ).withValues(alpha: 0.35),
      ),
      child: card,
    );
  }

  Widget _card(BuildContext context, EdgeInsets insets) {
    return Padding(
      padding: insets,
      child: ConstrainedBox(
        // Every card, the same height. See [nexCardHeightFor] — which is
        // [nexCardHeight] at the default text size, and only grows if someone
        // has turned the text up past what the glyph's 48 can hold.
        //
        // An expanded card turns that into a floor: it grows to whatever its
        // note needs, and still never sits shorter than the row every other
        // card keeps.
        constraints: expanded
            ? BoxConstraints(minHeight: nexCardHeightFor(context))
            : BoxConstraints.tightFor(height: nexCardHeightFor(context)),
        child: Semantics(
          button: onTap != null,
          selected: selected,
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
            showDue: showDue,
            expanded: expanded,
            selected: selected,
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
    // Stripped for the same reason the preview below is: a screen reader
    // reading "asterisk asterisk done asterisk asterisk" is the audible
    // version of the card showing its own source.
    NexMarkdownText.preview(note.displayText ?? ''),
    if (note.attachmentCount > 0) strings.attachedLabel(note.attachmentCount),
    strings.relativeTime(nexRelativeTimeOf(note.createdAt)),
  ].where((value) => value.isNotEmpty).join('. ');
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.note,
    required this.onTap,
    required this.previewOverride,
    required this.strings,
    required this.showDue,
    required this.expanded,
    required this.selected,
  });

  final Note note;
  final VoidCallback? onTap;
  final Widget? previewOverride;
  final NexCardStrings strings;
  final bool showDue;
  final bool expanded;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = selected ?? false;
    return Material(
      // The card's own fill, not the page's. They used to be the same
      // colour, which left a 1.2:1 hairline as the only thing marking the
      // boundary of the app's main tap target.
      color: picked
          ? Color.alphaBlend(
              theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
              theme.colorScheme.surfaceContainerLowest,
            )
          : theme.colorScheme.surfaceContainerLowest,
      // A quiet hairline separates the target from low-contrast backgrounds.
      // High-contrast mode uses the full outline and a thicker edge.
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        side: picked
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : MediaQuery.highContrastOf(context)
            ? BorderSide(color: theme.colorScheme.outline, width: 1.5)
            : context.nexVisualStyle.liquidGlass
            ? BorderSide(color: context.nexVisualStyle.glassBorder)
            : BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.6),
                width: 0.75,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(NexCardDensity.of(context).inset),
          child: Row(
            // Keep the icon aligned with the top of an expanded preview.
            crossAxisAlignment: expanded
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (selected case final picked?)
                _PickMark(picked: picked, note: note, strings: strings)
              else
                _LeadingWithPin(note: note, strings: strings),
              const SizedBox(width: NexSpacing.contentGap),
              Expanded(
                child: _withFootnote(
                  context,
                  previewOverride ??
                      _Preview(
                        note: note,
                        expanded: expanded,
                        strings: strings,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _CardBody {
  /// The note's words, and under them — only when there is one — a quiet
  /// footnote of what it carries besides: when it will remind, and how many
  /// more files it holds.
  ///
  /// It was a column at the end of the row, one pill above the other, and it
  /// took its width from every line of the note beside it; on a short card
  /// the two pills were as wide as the words. Under the words they cost one
  /// small line, on the cards that have them, and the words keep the card.
  Widget _withFootnote(BuildContext context, Widget preview) {
    final due = showDue ? note.dueAt : null;
    final attached = note.attachmentCount > 0;
    if (due == null && !attached) return preview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        preview,
        const SizedBox(height: NexSpacing.xs),
        Wrap(
          spacing: NexSpacing.md,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // A reminder still to come stays in the accent: it is the one
            // thing here that asks for something.
            if (due != null)
              _DueChip(
                due: due,
                label: strings.dueLabel?.call(due, note.dueRepeat),
                // A lapsed reminder is not an alarm any more. A repeating
                // one never lapses: it is always about to happen again.
                upcoming:
                    note.dueRepeat != NoteRepeat.once ||
                    due.isAfter(DateTime.now().toUtc()),
              ),
            if (attached)
              _AttachedMark(label: strings.attachedShort(note.attachmentCount)),
          ],
        ),
      ],
    );
  }
}

/// The files a note carries after its own, in the card's footnote: a
/// paperclip and "+3". Not on the leading square, whose corners already hold
/// the tag dots and the pin. Announced with the card (see `attachedLabel`),
/// so the mark itself is silent.
class _AttachedMark extends StatelessWidget {
  const _AttachedMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
      return Icon(Icons.notifications_active_outlined, size: 14, color: color);
    }
    // No box of its own: a line of the card's footnote, not a chip on it.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.notifications_active_outlined, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
      label: strings.tagList(
        tags.map((tag) => strings.tagName?.call(tag) ?? tag.name).join(', '),
      ),
      excludeSemantics: true,
      child: SizedBox(
        width: NexCardDensity.of(context).leading,
        height: NexCardDensity.of(context).leading,
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
  const _Preview({
    required this.note,
    required this.expanded,
    required this.strings,
  });
  final NexCardStrings strings;

  final Note note;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    // A checklist and a link both have a shape worth showing at a glance, and
    // both fit the same two lines every other card gets. Neither is
    // interactive here: the card's own tap opens the note, and a checkbox
    // inside a tappable card is a target inside a target.
    if (note.type == NoteType.checklist && note.checklistItems.isNotEmpty) {
      return _ChecklistPreview(items: note.checklistItems, expanded: expanded);
    }
    if (note.type == NoteType.link) return _LinkPreview(note: note);

    // The card is a picture of the note, not the note: a body someone made
    // bold shows as bold text would, without the asterisks that made it so.
    // Rendering Markdown here instead was considered and is wrong — a card is
    // two lines of a fixed height, and a heading or a list inside one would
    // fight that.
    final text = NexMarkdownText.preview(
      note.displayText ?? strings.noteOfType(note.type.name),
    );
    // Through [NexTextSurface] rather than a `Text` of its own, for the one
    // thing that widget does which a `Text` cannot: give each line of a
    // multi-line note its own direction. One direction over the whole
    // preview is the first line's direction imposed on the rest, so a note
    // that opens in English laid its Persian lines out left to right — and
    // the other way round for a note that opens in Persian, which is why it
    // only ever looked wrong on some cards.
    //
    // A note on one long line is unaffected: it still wraps into the whole
    // budget. Only a note that already has line breaks now spends that
    // budget in its own lines.
    final preview = NexTextSurface(
      text,
      // Two lines — see [nexCardPreviewLines], which the card's fixed height
      // is derived from. One line was enough to tell cards apart and not
      // enough to tell you what a note said: a captured thought is usually a
      // sentence, and a sentence is usually wider than a phone.
      //
      // Expanded, the card grows to the note — up to
      // [nexCardExpandedMaxLines]. The point of asking for it is that the
      // note is longer than two lines and you want to read it without opening
      // anything; the ceiling is there because a note long enough to need
      // scrolling is one the card cannot show anyway, and trying costs the
      // rest of the timeline its place on screen.
      maxLines: expanded
          ? nexCardExpandedMaxLines
          : note.type == NoteType.voice && (note.durationMs ?? 0) > 0
          ? 1
          : NexCardDensity.of(context).lines,
      style: NexCardDensity.of(context).previewStyle(Theme.of(context)),
    );
    // The card already announces its type. Keep real note content reachable,
    // but do not announce the translated empty-media fallback a second time.
    if (note.type == NoteType.voice && (note.durationMs ?? 0) > 0) {
      final seconds = note.durationMs! ~/ 1000;
      final duration =
          strings.durationLabel?.call(note.durationMs!) ??
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          preview,
          Text(
            duration,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      );
    }
    return note.displayText == null
        ? ExcludeSemantics(child: preview)
        : preview;
  }
}

/// The first two items of a checklist, ticked or not, plus what is left over —
/// or all of them, on a card asked to show its whole note.
///
/// Two, because that is what the card has room for — and the two that matter
/// are the ones still to do, so unticked items come first regardless of where
/// they sit in the list. A card showing "milk, bread" you have already bought
/// is a card telling you nothing.
///
/// The ordering holds when expanded too: a seven-item list still leads with
/// what is left to do. That is the same list, not a different view of it —
/// and an expanded card is bounded by [nexCardExpandedMaxLines] like any
/// other, so a hundred-item shopping list carries "+88" on its last line
/// rather than swallowing the timeline.
class _ChecklistPreview extends StatelessWidget {
  const _ChecklistPreview({required this.items, required this.expanded});

  final List<ChecklistItem> items;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...items.where((item) => !item.done),
      ...items.where((item) => item.done),
    ];
    final lines = NexCardDensity.of(context).lines;
    final shown = ordered
        .take(expanded ? nexCardExpandedMaxLines : lines)
        .toList();
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
          if (shown.length < lines)
            // Holds the card's height steady when a list has one item, the
            // same way a one-line text note reserves its second line.
            SizedBox(
              height:
                  nexCardPreviewLineHeightFor(context) * (lines - shown.length),
            ),
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
    return SizedBox(
      // Scaled, not 24: the row has to grow with the text inside it, or the
      // card gets taller (see [nexCardHeightFor]) around a line still being
      // squeezed into a box built for the default size.
      height: nexCardPreviewLineHeightFor(context),
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
            child: NexTextSurface.line(
              item.text,
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
    final headline = NexMarkdownText.preview(
      note.displayText ?? note.linkUrl ?? '',
    );
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            // Same reason as [_ChecklistLine]: the reserved row follows the
            // text size rather than pinning it at the default.
            height: nexCardPreviewLineHeightFor(context),
            child: NexTextSurface.line(
              headline,
              style: NexCardDensity.of(context).previewStyle(theme),
            ),
          ),
          SizedBox(
            height: nexCardPreviewLineHeightFor(context),
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
          width: NexCardDensity.of(context).leading,
          height: NexCardDensity.of(context).leading,
          cacheWidth: (NexCardDensity.of(context).leading * ratio).round(),
          // Decode at this width and keep the source aspect ratio. BoxFit
          // crops the resulting image into the square without stretching it.
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const _IconBox(Icons.image_not_supported_outlined, type: 'photo'),
        ),
      );
    }
    return _IconBox(
      nexNoteTypeIcon(note.type.wireName),
      type: note.type.wireName,
    );
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

/// The card's icon while cards are being picked: a tick in the accent when
/// this one is picked, the icon with an empty ring when it is not.
class _PickMark extends StatelessWidget {
  const _PickMark({
    required this.picked,
    required this.note,
    required this.strings,
  });

  final bool picked;
  final Note note;
  final NexCardStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = NexCardDensity.of(context).leading;
    if (picked) {
      return Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(NexRadius.cardLeading),
        ),
        child: Icon(Icons.check_rounded, color: scheme.onPrimary),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _LeadingWithPin(note: note, strings: strings),
        PositionedDirectional(
          top: -NexSpacing.xs,
          start: -NexSpacing.xs,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerLowest,
              border: Border.all(color: scheme.outline, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// The type's glyph on a wash of the type's colour — see [nexNoteTypeTint].
///
/// High contrast keeps the plain square and the full-strength ink: a tinted
/// glyph on a tinted ground is the colour doing the work, and that mode is
/// for when colour is not enough.
class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, {required this.type});
  final IconData icon;

  /// The note type's wire name.
  final String type;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = NexCardDensity.of(context).leading;
    final plain = MediaQuery.highContrastOf(context);
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: plain
            ? scheme.surfaceContainerHighest
            : nexNoteTypeWash(type, scheme),
        borderRadius: BorderRadius.circular(NexRadius.cardLeading),
      ),
      child: Icon(
        icon,
        color: plain ? scheme.onSurface : nexNoteTypeTint(type, scheme),
      ),
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
    label: Text(strings.tagName?.call(tag) ?? tag.name),
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

/// The short strands in the gutter above and below a card — see
/// [NoteCard.threadAbove].
class _ThreadPainter extends CustomPainter {
  _ThreadPainter({
    required this.above,
    required this.below,
    required this.insets,
    required this.offset,
    required this.direction,
    required this.color,
  });

  final bool above;
  final bool below;
  final EdgeInsets insets;
  final double offset;
  final TextDirection direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = direction == TextDirection.rtl
        ? size.width - insets.right - offset
        : insets.left + offset;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (above) canvas.drawLine(Offset(x, 0), Offset(x, insets.top), paint);
    if (below) {
      canvas.drawLine(
        Offset(x, size.height - insets.bottom),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) =>
      old.above != above ||
      old.below != below ||
      old.insets != insets ||
      old.offset != offset ||
      old.direction != direction ||
      old.color != color;
}
