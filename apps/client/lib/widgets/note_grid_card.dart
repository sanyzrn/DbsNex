import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../desktop/desktop_note_card.dart' show nexSplitNoteText;
import '../l10n/app_localizations.dart';

/// A note as a tile in the timeline's grid view (2.6.27): two to a row, each
/// washed in its kind's own colour — the accent's fan that already tints the
/// list's icons — with the kind's round mark at the top, what it says in the
/// middle, and when at the foot.
///
/// The list stays the default; this is the second way of looking at the same
/// notes. Everything a card does in the list it does here: a tap opens the
/// note, a hold opens its menu, and a tap on the round mark picks it.
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
      MediaQuery.textScalerOf(context).scale(176).clamp(176, 260);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final tint = nexNoteTypeTint(note.type.wireName, scheme);
    final picked = selected ?? false;
    final fill = Color.alphaBlend(
      tint.withValues(alpha: picked ? 0.32 : (dark ? 0.2 : 0.16)),
      scheme.surfaceContainerLowest,
    );
    final content = nexSplitNoteText(note, strings);
    final title = content.title.isNotEmpty ? content.title : content.body;
    final duration = note.type == NoteType.voice && (note.durationMs ?? 0) > 0
        ? strings.durationLabel?.call(note.durationMs!) ?? ''
        : '';
    final body = content.title.isNotEmpty ? content.body : duration;
    // The kind in one word — "Voice", not "Voice note": the tile is a note.
    final kind = AppLocalizations.of(context).noteType(note.type.wireName);
    final muted = scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: [
        strings.noteOfType(note.type.name),
        title,
        if (note.isUrgent) strings.urgentLabel,
        strings.relativeTime(nexRelativeTimeOf(note.updatedAt)),
      ].where((part) => part.isNotEmpty).join('. '),
      explicitChildNodes: true,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.xl),
          side: picked
              ? BorderSide(color: scheme.primary, width: 2)
              : MediaQuery.highContrastOf(context)
              ? BorderSide(color: scheme.outline, width: 1.5)
              : BorderSide(color: tint.withValues(alpha: dark ? 0.32 : 0.22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Mark(
                      note: note,
                      tint: tint,
                      selected: selected,
                      ringing: ringing,
                      label: strings.selectLabel,
                      onTap: onLeadingTap,
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    Expanded(
                      child: Text(
                        kind,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: nexReadableOn(tint, fill),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (note.pinnedAt != null)
                      Icon(Icons.push_pin, size: 14, color: muted),
                    if (note.isUrgent)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: Icon(
                          Icons.priority_high_rounded,
                          size: 16,
                          color: scheme.error,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: NexSpacing.sm),
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: nexDirectionOf(title),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: nexDirectionOf(body),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ],
                const Spacer(),
                Row(
                  children: [
                    if (note.dueAt != null) ...[
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 14,
                        color: muted,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        strings.relativeTime(nexRelativeTimeOf(note.updatedAt)),
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: nexReadableOn(tint, fill),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The round mark: the kind's icon on a light disc, a tick while picked.
class _Mark extends StatelessWidget {
  const _Mark({
    required this.note,
    required this.tint,
    required this.selected,
    required this.ringing,
    required this.label,
    required this.onTap,
  });

  final Note note;
  final Color tint;
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
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: picked
            ? scheme.primary
            : scheme.surfaceContainerLowest.withValues(alpha: 0.85),
        border: selected == false
            ? Border.all(color: scheme.outline, width: 1.5)
            : null,
      ),
      child: Icon(icon, size: 20, color: picked ? scheme.onPrimary : tint),
    );
    final tap = onTap;
    if (tap == null) return disc;
    return Semantics(
      button: true,
      selected: picked,
      label: label,
      child: InkResponse(
        key: ValueKey('note-pick-${note.id}'),
        onTap: tap,
        customBorder: const CircleBorder(),
        radius: 24,
        child: disc,
      ),
    );
  }
}
