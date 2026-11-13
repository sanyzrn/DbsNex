import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../desktop/desktop_note_card.dart' show nexSplitNoteText;
import '../l10n/app_localizations.dart';

/// How a grid tile is laid out at each card size (Settings → Appearance →
/// Card size): how many fit across, how tall a row is, and how large the
/// round mark is. Compact is three to a row on a phone; the others two.
@immutable
class NexGridMetrics {
  const NexGridMetrics._({
    required this.minColumns,
    required this.tileWidth,
    required this.height,
    required this.padding,
    required this.disc,
    required this.showKind,
  });

  final int minColumns;

  /// The width a tile is drawn for; a wider window fits more of them.
  final double tileWidth;

  /// A row's height at the reader's own text size of 1.
  final double height;
  final double padding;
  final double disc;

  /// Whether the kind's name sits beside the mark. A third of a phone is
  /// too narrow for it; the mark alone says it there.
  final bool showKind;

  static const _compact = NexGridMetrics._(
    minColumns: 3,
    tileWidth: 130,
    height: 172,
    padding: NexSpacing.sm + 2,
    disc: 30,
    showKind: false,
  );
  static const _standard = NexGridMetrics._(
    minColumns: 2,
    tileWidth: 190,
    height: 208,
    padding: NexSpacing.md - 2,
    disc: 36,
    showKind: true,
  );
  static const _readable = NexGridMetrics._(
    minColumns: 2,
    tileWidth: 230,
    height: 248,
    padding: NexSpacing.md,
    disc: 40,
    showKind: true,
  );

  static NexGridMetrics of(BuildContext context) =>
      switch (NexCardDensity.of(context)) {
        NexCardDensity.compact => _compact,
        NexCardDensity.standard => _standard,
        NexCardDensity.readable => _readable,
      };

  /// How many tiles fit across [width].
  int columnsFor(double width) =>
      (width / tileWidth).floor().clamp(minColumns, 8);

  /// The row height at the reader's text size, so larger text gets taller
  /// tiles rather than fewer words.
  double heightFor(BuildContext context) =>
      MediaQuery.textScalerOf(context)
          .scale(height)
          .clamp(height, height * 1.7);
}

/// A note as a tile in the timeline's grid view (2.6.27, reworked in 2.6.28).
///
/// A soft wash of the note kind's own colour — the accent's fan that tints the
/// list's icons — fading across the tile; the kind's round mark and the
/// note's marks (urgent, attached, pinned) at the top; then as much of the
/// note as fits: its words, the open items of a checklist, the photo itself,
/// a voice note's length, a link's site; and at the foot the reminder with
/// its time, and when it was last touched.
///
/// Everything a card does in the list it does here: a tap opens the note, a
/// hold opens its menu, and a tap on the round mark picks it.
class NexNoteGridCard extends StatelessWidget {
  const NexNoteGridCard({
    super.key,
    required this.note,
    required this.strings,
    required this.onTap,
    this.onLeadingTap,
    this.selected,
    this.ringing = false,
  });

  final Note note;
  final NexCardStrings strings;
  final VoidCallback onTap;

  /// A tap on the round mark: picks the note, or puts it back.
  final VoidCallback? onLeadingTap;

  /// Null when nothing is being picked; otherwise whether this one is.
  final bool? selected;
  final bool ringing;

  /// The height every tile in a row shares, at the reader's text size.
  static double heightFor(BuildContext context) =>
      NexGridMetrics.of(context).heightFor(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final metrics = NexGridMetrics.of(context);
    final tint = nexNoteTypeTint(note.type.wireName, scheme);
    final picked = selected ?? false;
    final ground = scheme.surfaceContainerLowest;
    // Quieter than a flat wash: the kind's colour gathers in one corner and
    // thins out across the tile, the way light falls on paper, so a screen
    // of tiles reads as colour without shouting it.
    Color wash(double alpha) =>
        Color.alphaBlend(tint.withValues(alpha: alpha), ground);
    final from = wash(picked ? 0.26 : (dark ? 0.15 : 0.13));
    final to = wash(picked ? 0.18 : (dark ? 0.05 : 0.035));
    final ink = nexReadableOn(tint, from);
    // The secondary tones, walked against this tile's own wash: the page's
    // muted grey fell under 4.5 on a coloured tile.
    final muted = nexReadableOn(scheme.onSurfaceVariant, from);
    final outline = nexReadableOn(scheme.outline, from);
    final content = nexSplitNoteText(note, strings);
    final kind = AppLocalizations.of(context).noteType(note.type.wireName);
    final highContrast = MediaQuery.highContrastOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: [
        strings.noteOfType(note.type.name),
        content.title.isNotEmpty ? content.title : content.body,
        if (note.isUrgent) strings.urgentLabel,
        if (note.dueAt case final due?)
          strings.dueDescription?.call(due, note.dueRepeat) ??
              strings.dueLabel?.call(due, note.dueRepeat) ??
              '',
        strings.relativeTime(nexRelativeTimeOf(note.updatedAt)),
      ].where((part) => part.isNotEmpty).join('. '),
      explicitChildNodes: true,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: ShapeDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [from, to],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NexRadius.xl),
              side: picked
                  ? BorderSide(color: scheme.primary, width: 2)
                  : highContrast
                  ? BorderSide(color: scheme.outline, width: 1.5)
                  : BorderSide(
                      color: tint.withValues(alpha: dark ? 0.22 : 0.14),
                    ),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NexRadius.xl),
            ),
            child: Padding(
              padding: EdgeInsets.all(metrics.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Top(
                    note: note,
                    kind: metrics.showKind ? kind : null,
                    tint: tint,
                    ink: ink,
                    muted: muted,
                    disc: metrics.disc,
                    selected: selected,
                    ringing: ringing,
                    label: strings.selectLabel,
                    onPick: onLeadingTap,
                  ),
                  SizedBox(height: metrics.padding * 0.8),
                  Expanded(
                    child: ClipRect(
                      child: _Body(
                        note: note,
                        title: content.title,
                        body: content.body,
                        strings: strings,
                        tint: tint,

                        muted: muted,
                        outline: outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  _Foot(
                    note: note,
                    strings: strings,
                    roomForBoth: metrics.showKind,
                    ground: from,
                    muted: muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round mark, the kind's name, and the note's marks.
class _Top extends StatelessWidget {
  const _Top({
    required this.note,
    required this.kind,
    required this.tint,
    required this.ink,
    required this.muted,
    required this.disc,
    required this.selected,
    required this.ringing,
    required this.label,
    required this.onPick,
  });

  final Note note;
  final String? kind;
  final Color tint;
  final Color ink;
  final Color muted;
  final double disc;
  final bool? selected;
  final bool ringing;
  final String label;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final marks = <Widget>[
      if (note.attachmentCount > 0)
        Icon(Icons.attach_file, size: 15, color: muted),
      if (note.pinnedAt != null) Icon(Icons.push_pin, size: 15, color: muted),
      // The list card's own urgent mark, so urgency looks the same in both
      // views.
      if (note.isUrgent)
        Icon(
          key: const ValueKey('note-urgent-mark'),
          Icons.local_fire_department_outlined,
          size: 17,
          color: scheme.error,
        ),
    ];
    return Row(
      children: [
        _Mark(
          note: note,
          tint: tint,
          size: disc,
          selected: selected,
          ringing: ringing,
          label: label,
          onTap: onPick,
        ),
        if (kind case final kind?) ...[
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              kind,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ] else
          const Spacer(),
        for (final mark in marks) ...[
          const SizedBox(width: 3),
          ExcludeSemantics(child: mark),
        ],
      ],
    );
  }
}

/// As much of the note as the tile has room for.
class _Body extends StatelessWidget {
  const _Body({
    required this.note,
    required this.title,
    required this.body,
    required this.strings,
    required this.tint,
    required this.muted,
    required this.outline,
  });

  final Note note;
  final String title;
  final String body;
  final NexCardStrings strings;
  final Color tint;
  final Color muted;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      height: 1.4,
    );
    final heading = title;
    final uri = note.mediaUri;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        double lineOf(TextStyle? style) =>
            scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.3);
        // Whole lines only: a line cut through the middle reads as a glitch.
        int fit(double height, TextStyle? style) =>
            (height / lineOf(style)).floor().clamp(1, 40);
        Widget headingText(int lines) => Text(
          heading,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          textDirection: nexDirectionOf(heading),
          style: titleStyle,
        );

        if (note.type == NoteType.photo && uri != null) {
          final caption = heading.isNotEmpty ? heading : body;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(NexRadius.md),
                  child: Image.file(
                    File(uri),
                    fit: BoxFit.cover,
                    cacheWidth:
                        (constraints.maxWidth *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: tint.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: outline,
                      ),
                    ),
                  ),
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.xs),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: nexDirectionOf(caption),
                  style: bodyStyle?.copyWith(color: scheme.onSurface),
                ),
              ],
            ],
          );
        }

        if (note.type == NoteType.checklist) {
          final items = note.checklistItems
              .where((item) => item.text.trim().isNotEmpty)
              .toList();
          final open = [
            ...items.where((i) => !i.done),
            ...items.where((i) => i.done),
          ];
          final rows = fit(
            constraints.maxHeight - (heading.isEmpty ? 0 : lineOf(titleStyle)),
            bodyStyle,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (heading.isNotEmpty) headingText(1),
              for (final item in open.take(rows))
                Row(
                  children: [
                    Icon(
                      item.done
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 15,
                      color: item.done ? tint : outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: nexDirectionOf(item.text),
                        style: bodyStyle?.copyWith(
                          color: item.done ? muted : scheme.onSurface,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          );
        }

        final extra = switch (note.type) {
          NoteType.voice when (note.durationMs ?? 0) > 0 =>
            strings.durationLabel?.call(note.durationMs!),
          NoteType.link => Uri.tryParse(note.linkUrl ?? '')?.host,
          _ => null,
        };
        final rest = body;
        // The heading takes up to three lines; the words under it every
        // whole line that is left.
        final headLines = heading.isEmpty
            ? 0
            : fit(constraints.maxHeight, titleStyle).clamp(1, 3);
        final used =
            headLines * lineOf(titleStyle) +
            (extra == null ? 0 : lineOf(bodyStyle) + 2);
        final restLines = fit(constraints.maxHeight - used, bodyStyle);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (heading.isNotEmpty) headingText(headLines),
            if (extra != null && extra.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      note.type == NoteType.voice
                          ? Icons.graphic_eq_rounded
                          : Icons.public_rounded,
                      size: 14,
                      color: tint,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        extra,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (rest.isNotEmpty && restLines > 0)
              Flexible(
                child: Text(
                  rest,
                  maxLines: restLines,
                  overflow: TextOverflow.ellipsis,
                  textDirection: nexDirectionOf(rest),
                  style: heading.isEmpty
                      ? bodyStyle?.copyWith(color: scheme.onSurface)
                      : bodyStyle,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The reminder with its time, the tags, and when the note was last touched.
class _Foot extends StatelessWidget {
  const _Foot({
    required this.note,
    required this.strings,
    required this.roomForBoth,
    required this.ground,
    required this.muted,
  });

  final Color muted;

  /// The tile's wash, which the reminder's words are read on.
  final Color ground;

  final Note note;
  final NexCardStrings strings;

  /// Whether the reminder and the time both fit. A compact tile is a third
  /// of a phone: there the reminder, with its time, has the foot to itself.
  final bool roomForBoth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.labelSmall?.copyWith(color: muted);
    final due = note.dueAt;
    Widget? reminder;
    if (due != null) {
      // The list card's colours: a reminder still ahead in the accent, one
      // that has already rung in the quiet outline.
      final upcoming =
          note.dueRepeat != NoteRepeat.once ||
          due.isAfter(DateTime.now().toUtc());
      // Read on the pill, which is the colour over the tile's wash.
      final base = upcoming ? scheme.primary : muted;
      final color = nexReadableOn(
        base,
        Color.alphaBlend(base.withValues(alpha: 0.12), ground),
      );
      final full = strings.dueLabel?.call(due, note.dueRepeat);
      final short = strings.dueCompactLabel?.call(due, note.dueRepeat);
      reminder = ExcludeSemantics(
        child: Container(
          key: const ValueKey('grid-reminder'),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(NexRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                note.dueRepeat == NoteRepeat.once
                    ? Icons.notifications_active_outlined
                    : Icons.repeat_rounded,
                size: 13,
                color: color,
              ),
              if (full != null) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final style = small?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      );
                      final painter = TextPainter(
                        text: TextSpan(text: full, style: style),
                        textScaler: MediaQuery.textScalerOf(context),
                        textDirection: Directionality.of(context),
                        maxLines: 1,
                      )..layout();
                      final fits = painter.width <= constraints.maxWidth;
                      painter.dispose();
                      return Text(
                        fits || short == null ? full : short,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final tags = note.tags.take(3).toList();
    final tagDots = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tag in tags)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: nexParseTagColor(tag.color) ?? scheme.outline,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
    // Both ends take only what they need, the reminder first; the time
    // stays at the far edge and gives way only when the row is full.
    if (reminder != null && !roomForBoth) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: reminder,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(flex: 3, child: reminder ?? tagDots),
        const SizedBox(width: NexSpacing.xs),
        Flexible(
          child: Text(
            strings.relativeTime(nexRelativeTimeOf(note.updatedAt)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small,
          ),
        ),
      ],
    );
  }
}

/// The round mark: the kind's icon on a light disc, a tick while picked.
class _Mark extends StatelessWidget {
  const _Mark({
    required this.note,
    required this.tint,
    required this.size,
    required this.selected,
    required this.ringing,
    required this.label,
    required this.onTap,
  });

  final Note note;
  final Color tint;
  final double size;
  final bool? selected;
  final bool ringing;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final picked = selected ?? false;
    final icon = picked
        ? Icons.check_rounded
        : ringing
        ? Icons.notifications_active_rounded
        : nexNoteTypeIcon(note.type.wireName);
    final disc = AnimatedContainer(
      duration: NexMotion.of(context, NexMotion.fast),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: picked
            ? scheme.primary
            : scheme.surfaceContainerLowest.withValues(alpha: 0.9),
        border: selected == false
            ? Border.all(color: scheme.outline, width: 1.5)
            : null,
      ),
      child: Icon(
        icon,
        size: size * 0.52,
        color: picked ? scheme.onPrimary : tint,
      ),
    );
    final tap = onTap;
    if (tap == null) return disc;
    // A touch target of at least 40 even where the disc is smaller.
    final target = size < 40 ? 40.0 : size;
    return Semantics(
      button: true,
      selected: picked,
      label: label,
      child: InkResponse(
        key: ValueKey('note-pick-${note.id}'),
        onTap: tap,
        customBorder: const CircleBorder(),
        radius: target / 2 + 2,
        child: SizedBox.square(
          dimension: target,
          child: Center(child: disc),
        ),
      ),
    );
  }
}
