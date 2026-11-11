import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../tokens/nex_relative_time.dart';
import '../tokens/nex_text_direction.dart';
import '../tokens/nex_tokens.dart';
import '../tokens/nex_appearance.dart';

part 'note_card_bell.dart';
part 'note_card_footnote.dart';
part 'note_card_collapsed.dart';

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
    this.dueDescription,
    this.dueCompactLabel,
    this.tagName,
    this.durationLabel,
    this.attachedShort = _defaultAttachedShort,
    this.attachedLabel = _defaultAttachedLabel,
    this.urgentLabel = 'Urgent',
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
  final String urgentLabel;

  /// Full schedule for the tooltip and screen reader.
  final String Function(DateTime due, NoteRepeat repeat)? dueDescription;

  /// A shorter label when the full reminder cannot fit, retaining its time.
  final String? Function(DateTime due, NoteRepeat repeat)? dueCompactLabel;
}

/// Whether expansion reveals content beyond this card's compact preview.
/// Measured at the real width, font and text scale, only when its menu opens.
bool nexNoteCanExpand(
  BuildContext context,
  Note note, {
  required double cardWidth,
  NexCardStrings strings = NexCardStrings.fallback,
}) {
  final density = NexCardDensity.of(context);
  final marked =
      note.dueAt != null || note.isUrgent || note.attachmentCount > 0;
  final captioned =
      note.type == NoteType.text && note.caption?.trim().isNotEmpty == true;
  final width =
      cardWidth -
      nexCardInsetsFor(context).horizontal -
      density.inset * 2 -
      density.leading -
      NexSpacing.contentGap;
  if (width <= 0) return true;
  if (note.type == NoteType.checklist && note.checklistItems.isNotEmpty) {
    return note.checklistItems.length > density.lines ||
        (marked && note.checklistItems.length == density.lines);
  }
  // Expansion moves the overlay below the site, caption or duration, exposing
  // any secondary text it may mask even when the main body fits.
  if (note.type == NoteType.link) return marked;
  if (marked &&
      (captioned ||
          (note.type == NoteType.voice && (note.durationMs ?? 0) > 0))) {
    return true;
  }
  final text = NexMarkdownText.preview(note.displayText ?? '');
  if (text.trim().isEmpty) return false;
  final budget = note.type == NoteType.voice && (note.durationMs ?? 0) > 0
      ? 1
      : density.lines -
            (note.type == NoteType.text &&
                    note.caption?.trim().isNotEmpty == true
                ? 1
                : 0);
  final lines = text
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
  final directions = {for (final line in lines) nexDirectionOf(line)}
    ..remove(null);
  var left = budget;
  final paragraphs = directions.length > 1 ? lines : [lines.join('\n')];
  for (final paragraph in paragraphs) {
    if (left <= 0) return true;
    final painter = TextPainter(
      text: TextSpan(
        text: paragraph,
        style: DefaultTextStyle.of(context).style
            .merge(density.previewStyle(Theme.of(context))),
      ),
      textDirection: nexDirectionOf(paragraph) ?? Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: left,
    )..layout(maxWidth: width);
    final overflow = painter.didExceedMaxLines;
    left -= painter.computeLineMetrics().length.clamp(1, left);
    painter.dispose();
    if (overflow) return true;
  }
  // A filled last row can be masked by the overlay. Expansion reveals it
  // without making the collapsed paragraph narrower or changing its wrapping.
  return (marked && left == 0) ||
      (text.split('\n').length > lines.length && text.trim().contains('\n\n'));
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
    this.ringing = false,
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

  /// Whether this note's reminder has rung and is waiting to be looked at:
  /// a swinging bell takes the place of the type icon until it is opened.
  final bool ringing;

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
    // A collapsed card's envelope depends only on density and text scaling.
    // Captions and status marks spend space inside it, for every note kind.
    final height = nexCardHeightFor(context);
    return Padding(
      padding: insets,
      child: ConstrainedBox(
        // All collapsed previews share the envelope; only an explicitly
        // expanded card can grow with its contents.
        constraints: expanded
            ? BoxConstraints(minHeight: height)
            : BoxConstraints.tightFor(height: height),
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
            ringing: ringing,
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
    if (note.isUrgent) strings.urgentLabel,
    if (note.type == NoteType.text && note.caption?.trim().isNotEmpty == true)
      NexMarkdownText.preview(note.caption!),
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
    this.ringing = false,
  });

  final bool ringing;
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
    final surfaceColor = picked
        ? Color.alphaBlend(
            theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
            theme.colorScheme.surfaceContainerLowest,
          )
        : theme.colorScheme.surfaceContainerLowest;
    return Material(
      // The card's own fill, not the page's. They used to be the same
      // colour, which left a 1.2:1 hairline as the only thing marking the
      // boundary of the app's main tap target.
      color: surfaceColor,
      // A quiet hairline separates the target from low-contrast backgrounds.
      // High-contrast mode uses the full outline and a thicker edge.
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        side:
            context.nexVisualStyle.minimal &&
                !MediaQuery.highContrastOf(context)
            ? BorderSide.none
            : picked
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : MediaQuery.highContrastOf(context)
            ? BorderSide(color: theme.colorScheme.outline, width: 1.5)
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
            crossAxisAlignment: expanded
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              _LeadingWithPin(
                note: note,
                strings: strings,
                backgroundColor: surfaceColor,
                ringing: ringing && selected == null,
                selected: selected,
                showDue: showDue,
              ),
              const SizedBox(width: NexSpacing.contentGap),
              Expanded(child: _withFootnote(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// At most three tag colours sit on the *top arc* of the circular icon.
/// They keep the card's own semantics and never consume preview width.
class _ArcTagDots extends StatelessWidget {
  const _ArcTagDots({
    required this.tags,
    required this.strings,
    required this.backgroundColor,
  });

  final List<Tag> tags;
  final NexCardStrings strings;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final shown = tags.take(nexMaxTagsPerNote).toList();
    final side = NexCardDensity.of(context).leading;
    // Clear separation for three dots, even at compact density.
    const dotDiameter = 10.0;
    const colorDiameter = 7.5;
    return Semantics(
      container: true,
      label: strings.tagList(
        tags.map((tag) => strings.tagName?.call(tag) ?? tag.name).join(', '),
      ),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: side,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left:
                    _noteOrbitCenter(
                      side,
                      (i - (shown.length - 1) / 2) *
                          (shown.length == 2 ? math.pi / 3 : math.pi / 4),
                      upper: true,
                    ).dx -
                    dotDiameter / 2,
                top:
                    _noteOrbitCenter(
                      side,
                      (i - (shown.length - 1) / 2) *
                          (shown.length == 2 ? math.pi / 3 : math.pi / 4),
                      upper: true,
                    ).dy -
                    dotDiameter / 2,
                child: Container(
                  key: ValueKey('note-tag-dot-$i'),
                  width: dotDiameter,
                  height: dotDiameter,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: backgroundColor,
                  ),
                  child: Container(
                    width: colorDiameter,
                    height: colorDiameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: nexParseTagColor(shown[i].color),
                      border: shown[i].color == null
                          ? Border.all(
                              color: Theme.of(context).colorScheme.outline,
                              width: 1,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
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
  const _Preview({
    required this.note,
    required this.expanded,
    required this.strings,
    required this.lines,
  });
  final NexCardStrings strings;

  final Note note;
  final bool expanded;

  /// The density's complete budget of preview lines.
  final int lines;

  @override
  Widget build(BuildContext context) {
    // A checklist and a link both have a shape worth showing at a glance, and
    // both fit the same two lines every other card gets. Neither is
    // interactive here: the card's own tap opens the note, and a checkbox
    // inside a tappable card is a target inside a target.
    if (note.type == NoteType.checklist && note.checklistItems.isNotEmpty) {
      return _ChecklistPreview(
        items: note.checklistItems,
        expanded: expanded,
        lines: lines,
      );
    }
    if (note.type == NoteType.link) {
      return _LinkPreview(note: note, showSite: expanded || lines > 1);
    }

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
          : lines,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
  const _ChecklistPreview({
    required this.items,
    required this.expanded,
    required this.lines,
  });

  final List<ChecklistItem> items;
  final bool expanded;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...items.where((item) => !item.done),
      ...items.where((item) => item.done),
    ];
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = math.min(
            NexSpacing.sm,
            math.max(0.0, (constraints.maxWidth - 16) / 4),
          );
          // The line follows its own words, not the interface's language: a
          // Persian item in an English interface (or the reverse) put the
          // checkbox on the opposite edge from the text it belongs to, with
          // the whole card's width of nothing between them. The words inside
          // already lay out by their own direction; the row now agrees.
          return Row(
            textDirection:
                nexDirectionOf(item.text) ?? Directionality.of(context),
            children: [
              Icon(
                item.done
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank,
                size: 16,
                color: item.done ? scheme.primary : scheme.onSurfaceVariant,
              ),
              SizedBox(width: gap),
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
                SizedBox(width: gap),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth:
                        math.max(0, constraints.maxWidth - 16 - gap * 2) * 0.35,
                  ),
                  child: Text(
                    trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A link note: what the page is called, and which site it is on.
///
/// The host on its own line is the part that stops a list of bookmarks from
/// being unreadable — titles repeat across a site, domains do not.
class _LinkPreview extends StatelessWidget {
  const _LinkPreview({required this.note, required this.showSite});

  final Note note;

  /// Whether the site has its row. Not when the footnote needs it.
  final bool showSite;

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
          if (showSite)
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
        // The photo shares the same circular outline as every note type.
        borderRadius: BorderRadius.circular(
          NexCardDensity.of(context).leading / 2,
        ),
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
class _LeadingWithPin extends StatefulWidget {
  const _LeadingWithPin({
    required this.note,
    required this.strings,
    required this.backgroundColor,
    this.ringing = false,
    this.selected,
    this.showDue = true,
  });
  final Note note;
  final NexCardStrings strings;
  final Color backgroundColor;
  final bool ringing;
  final bool? selected;
  final bool showDue;

  @override
  State<_LeadingWithPin> createState() => _LeadingWithPinState();
}

class _LeadingWithPinState extends State<_LeadingWithPin>
    with SingleTickerProviderStateMixin {
  // No ticker until a real marker change; scrolling does not replay a pulse.
  AnimationController? _pulse;

  Object _markers(Note note) => (
    note.pinnedAt != null,
    Object.hashAll(note.tags.map((tag) => (tag.id, tag.color))),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _pulse?.stop();
      _pulse?.value = 1;
    }
  }

  @override
  void didUpdateWidget(_LeadingWithPin old) {
    super.didUpdateWidget(old);
    if (old.note.id != widget.note.id ||
        _markers(old.note) == _markers(widget.note)) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _pulse?.stop();
      _pulse?.value = 1;
      return;
    }
    final pulse = _pulse ??= AnimationController(
      vsync: this,
      duration: NexMotion.pop,
    );
    pulse.forward(from: 0);
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _LeadingMarkers(
      note: widget.note,
      strings: widget.strings,
      backgroundColor: widget.backgroundColor,
      ringing: widget.ringing,
      selected: widget.selected,
      showDue: widget.showDue,
    );
    final pulse = _pulse;
    if (pulse == null) return child;
    return AnimatedBuilder(
      animation: pulse,
      child: child,
      builder: (context, child) {
        final t = MediaQuery.disableAnimationsOf(context) ? 1.0 : pulse.value;
        return Transform.scale(
          key: ValueKey('note-marker-pulse-${widget.note.id}'),
          scale: 1 + 0.08 * 4 * t * (1 - t),
          child: child,
        );
      },
    );
  }
}

/// Every marker shares one fixed center, whether or not statuses exist.
Offset _noteOrbitCenter(double side, double angle, {required bool upper}) {
  final radius = side / 2;
  return Offset(
    radius + radius * math.sin(angle),
    radius + (upper ? -1 : 1) * radius * math.cos(angle),
  );
}

/// With three statuses, fit their full hit areas inside the leading square.
double _noteStatusBadgeSize(BuildContext context, int count) {
  final density = NexCardDensity.of(context);
  final normal = switch (density) {
    NexCardDensity.compact => 14.0,
    NexCardDensity.standard => 16.0,
    NexCardDensity.readable => 18.0,
  };
  // Three badges need a little breathing room around the lower arc,
  // including the compact 40px circle. Larger badges remain unchanged.
  return count == 3 ? math.min(normal, density.leading / 3 - 2) : normal;
}

class _LeadingMarkers extends StatelessWidget {
  const _LeadingMarkers({
    required this.note,
    required this.strings,
    required this.backgroundColor,
    this.ringing = false,
    this.selected,
    this.showDue = true,
  });

  final Note note;
  final NexCardStrings strings;
  final Color backgroundColor;
  final bool ringing;
  final bool? selected;
  final bool showDue;

  @override
  Widget build(BuildContext context) {
    final side = NexCardDensity.of(context).leading;
    final leading = selected != null
        ? _PickMark(
            picked: selected!,
            note: note,
            backgroundColor: backgroundColor,
          )
        : ringing
        ? const _RingingBell()
        : _Leading(note: note);
    final hasStatuses =
        (showDue && note.dueAt != null) ||
        note.attachmentCount > 0 ||
        note.isUrgent;
    return SizedBox.square(
      key: const ValueKey('note-leading-orbit'),
      dimension: side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Status badges do not move the type, selection or ringing circle.
          KeyedSubtree(
            key: const ValueKey('note-main-circle'),
            child: KeyedSubtree(
              key: const ValueKey('note-main-circle-paint'),
              child: leading,
            ),
          ),
          if (note.tags.isNotEmpty)
            _ArcTagDots(
              tags: note.tags,
              strings: strings,
              backgroundColor: backgroundColor,
            ),
          if (hasStatuses)
            _CardStatusMarks(
              note: note,
              strings: strings,
              backgroundColor: backgroundColor,
              due: showDue ? note.dueAt : null,
            ),
          // Pin badge is temporarily hidden. Pinning and Pinned group remain.
        ],
      ),
    );
  }
}

/// The selection keeps the exact same circle and orbit of badges.
/// A picked card uses a check; an unpicked card keeps its type icon and a
/// small selection ring on the left, away from the top tags.
class _PickMark extends StatelessWidget {
  const _PickMark({
    required this.picked,
    required this.note,
    required this.backgroundColor,
  });

  final bool picked;
  final Note note;
  final Color backgroundColor;

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
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check_rounded, color: scheme.onPrimary),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _Leading(note: note),
        PositionedDirectional(
          start: -6,
          top: (side - 18) / 2,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
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
        shape: BoxShape.circle,
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
