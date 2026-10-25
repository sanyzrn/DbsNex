import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../screens/note_detail_sheet.dart';
import 'nex_banner.dart';
import 'nex_dialog.dart';

/// The pieces the Library's collections share (2.3.0): Archive, Trash, Tags
/// and Threads.
///
/// They used to be one grey block of rows each, joined edge to edge, so a
/// list of notes read as one slab with lines in it. Each collection now
/// opens on a header that says what it holds and how much, and its items are
/// separate cards with room between them, a coloured edge saying what kind
/// of thing each is, and the facts that matter for that collection (when it
/// comes back, when it goes for good) as small chips.

/// The top of a collection: what it is, how many, and one line on what it is
/// for.
class NexCollectionHero extends StatelessWidget {
  const NexCollectionHero({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final Color color;
  final int count;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    return Container(
      margin: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.md,
      ),
      padding: const EdgeInsets.all(NexSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NexRadius.xl),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.alphaBlend(
              color.withValues(alpha: 0.16),
              scheme.surfaceContainerLow,
            ),
            Color.alphaBlend(
              color.withValues(alpha: 0.04),
              scheme.surfaceContainerLow,
            ),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: count.toDouble()),
                      duration: NexMotion.of(context, NexMotion.receipt),
                      curve: NexMotion.curve,
                      builder: (context, value, _) => Text(
                        nexDigits('${value.round()}', persian: persian),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A label over a run of cards, with a hairline running off from it.
class NexCollectionSection extends StatelessWidget {
  const NexCollectionSection({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md + NexSpacing.xs,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.sm,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: NexSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(child: Divider(color: scheme.outlineVariant, height: 1)),
        ],
      ),
    );
  }
}

/// A small fact on a card: an icon and a few words.
class NexMetaChip extends StatelessWidget {
  const NexMetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(NexRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: tint),
            ),
          ),
        ],
      ),
    );
  }
}

/// One thing in a collection, as its own card.
///
/// [accent] colours its leading edge. [onSwipe], when given, is what a swipe
/// from the start edge does — the collection's one gentle action (bring back,
/// restore) — shown under the card as it moves with [swipeIcon] and
/// [swipeLabel]. [progress] draws a thin bar along the bottom (how much of
/// the trash's thirty days is left).
class NexCollectionTile extends StatelessWidget {
  const NexCollectionTile({
    super.key,
    required this.leading,
    required this.title,
    this.meta = const [],
    this.trailing,
    this.onTap,
    this.accent,
    this.progress,
    this.onSwipe,
    this.swipeIcon,
    this.swipeLabel,
  });

  final Widget leading;
  final Widget title;
  final List<Widget> meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? accent;
  final double? progress;
  final VoidCallback? onSwipe;
  final IconData? swipeIcon;
  final String? swipeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final edge = accent ?? scheme.primary;
    Widget card = Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: edge.withValues(alpha: 0.75)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    NexSpacing.md,
                    NexSpacing.md,
                    NexSpacing.sm,
                    NexSpacing.md,
                  ),
                  child: Row(
                    children: [
                      leading,
                      const SizedBox(width: NexSpacing.md),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DefaultTextStyle.merge(
                              style: theme.textTheme.bodyLarge,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              child: title,
                            ),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: NexSpacing.xs + 2),
                              Wrap(
                                spacing: NexSpacing.xs,
                                runSpacing: NexSpacing.xs,
                                children: meta,
                              ),
                            ],
                            if (progress case final value?) ...[
                              const SizedBox(height: NexSpacing.sm),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  NexRadius.xs,
                                ),
                                child: LinearProgressIndicator(
                                  value: value.clamp(0.0, 1.0),
                                  minHeight: 3,
                                  color: edge,
                                  backgroundColor: edge.withValues(alpha: 0.12),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: NexSpacing.xs),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (onSwipe case final swipe?) {
      card = Dismissible(
        key: key ?? UniqueKey(),
        // Toward the start edge (2.3.1): the other way is the page's own
        // swipe back, and a card took that gesture over.
        direction: DismissDirection.endToStart,
        onDismissed: (_) => swipe(),
        background: Container(
          decoration: BoxDecoration(
            color: edge.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(NexRadius.lg),
          ),
          padding: const EdgeInsetsDirectional.only(end: NexSpacing.lg),
          alignment: AlignmentDirectional.centerEnd,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(swipeIcon ?? Icons.check, color: edge),
              if (swipeLabel != null) ...[
                const SizedBox(width: NexSpacing.sm),
                Text(
                  swipeLabel!,
                  style: theme.textTheme.labelLarge?.copyWith(color: edge),
                ),
              ],
            ],
          ),
        ),
        child: card,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        0,
        NexSpacing.md,
        NexSpacing.sm,
      ),
      child: card,
    );
  }
}

/// A note's kind, as the square on its card: its type's icon on its type's
/// wash.
class NexNoteKindSquare extends StatelessWidget {
  const NexNoteKindSquare({super.key, required this.type});

  final NoteType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: nexNoteTypeWash(type.wireName, scheme),
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      child: Icon(
        nexNoteTypeIcon(type.wireName),
        color: nexNoteTypeTint(type.wireName, scheme),
      ),
    );
  }
}

/// "3d ago", in the language the user chose — the same bucketing the cards
/// use, so a note's card and its collection row agree about time.
String nexTimeAgo(BuildContext context, DateTime when) {
  final l10n = AppLocalizations.of(context);
  final time = nexRelativeTimeOf(when);
  return switch (time.unit) {
    NexRelativeUnit.now => l10n.timeNow,
    NexRelativeUnit.minutes => l10n.timeMinutesAgo(time.count),
    NexRelativeUnit.hours => l10n.timeHoursAgo(time.count),
    NexRelativeUnit.days => l10n.timeDaysAgo(time.count),
    NexRelativeUnit.weeks => l10n.timeWeeksAgo(time.count),
    NexRelativeUnit.months => l10n.timeMonthsAgo(time.count),
    NexRelativeUnit.years => l10n.timeYearsAgo(time.count),
  };
}

/// Whole calendar days from today to [when] (0 for today, negative if past).
int nexDaysUntil(DateTime when, {DateTime? now}) {
  final local = when.toLocal();
  final today = now ?? DateTime.now();
  return DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
}

/// What a collection card says a note is: its words, or its kind.
String nexNoteHeadline(Note note, AppLocalizations l10n) {
  final text = note.searchableDerivedText?.trim() ?? '';
  return text.isNotEmpty ? text : l10n.noteType(note.type.wireName);
}

/// Opens a note's details from a collection, and does what the sheet asked
/// for when it closes — Delete, with Undo — the way the timeline does. The
/// collections used to drop that answer, so Delete there closed the sheet and
/// left the note where it was.
Future<void> nexOpenNoteFromCollection(
  BuildContext context, {
  required NexServices services,
  required NexPreferences? preferences,
  required Note note,
}) async {
  final result = await nexShowSheet<DetailResult>(
    context: context,
    builder: (_) => NoteDetailSheet(
      services: services,
      preferences: preferences,
      noteId: note.id,
      initialNote: note,
    ),
  );
  if (result == DetailResult.deleted && context.mounted) {
    await nexDeleteNoteWithUndo(
      context,
      services: services,
      preferences: preferences,
      note: note,
    );
  }
  await services.refreshTimeline();
}

/// Asks before something the page cannot take back with an Undo — emptying
/// the trash, or one of the archive's "all" actions. True only on a yes.
Future<bool> nexConfirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
}) async {
  final l10n = AppLocalizations.of(context);
  final ok = await nexShowDialog<bool>(
    context: context,
    builder: (ctx) => NexAlertDialog(
      title: Text(title),
      content: NexDialogBody(child: Text(body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Moves a note to the trash and offers Undo.
Future<void> nexDeleteNoteWithUndo(
  BuildContext context, {
  required NexServices services,
  required NexPreferences? preferences,
  required Note note,
  VoidCallback? onUndone,
}) async {
  final l10n = AppLocalizations.of(context);
  if (preferences?.haptics ?? true) unawaited(HapticFeedback.mediumImpact());
  await services.deleteNote(note.id);
  await services.refreshTimeline();
  if (!context.mounted) return;
  nexShowBanner(
    context,
    message: l10n.noteDeleted,
    haptics: preferences?.haptics ?? true,
    actionLabel: l10n.undo,
    onAction: () async {
      await services.undelete(note.id);
      await services.refreshTimeline();
      onUndone?.call();
    },
  );
}
