import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';

class EmptyTimeline extends StatelessWidget {
  const EmptyTimeline({
    super.key,
    this.onWrite,
    this.onSpeak,
    this.onPhotograph,
    this.setAsideCount = 0,
    this.onShowSetAside,
  });

  /// What each example row does when tapped: the first note, started from
  /// the row that describes it (1.94.0). An empty library used to only
  /// explain itself; the capture button was the one way in.
  final VoidCallback? onWrite;
  final VoidCallback? onSpeak;
  final VoidCallback? onPhotograph;

  /// How many notes are set aside. When there are some, an empty home screen is
  /// not an empty library, and telling a person with forty notes to "write the
  /// first one" would be wrong: it says everything is clear and offers a way
  /// to the notes that are waiting instead.
  final int setAsideCount;
  final VoidCallback? onShowSetAside;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (setAsideCount > 0) return _clear(context, l10n, theme);
    // The clearance is reserved *outside* the Center, which is the whole
    // point. It used to be bottom padding on the scroll view, inside the
    // centred block — so it moved the content up by half of itself and left
    // the rest of it under the capture button, which is anchored to the
    // viewport rather than to this column. On a desktop window, where the
    // empty state is shorter than the space it sits in, the last line came out
    // directly beneath the button.
    return Padding(
      padding: EdgeInsets.only(
        bottom: nexFabClearance + nexBottomInset(context),
      ),
      child: Center(
        child: SingleChildScrollView(
          // md rather than lg above: the ghosts below are drawn to the real
          // card's inset now, which made the block taller than the room a
          // desktop window leaves between the filter row and the capture
          // button. The gap that gave way is decoration; the card geometry is
          // the part that carries meaning.
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.lg,
            NexSpacing.md,
            NexSpacing.lg,
            NexSpacing.md,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Text(
                  l10n.emptyPromise,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: NexSpacing.sm),
                Text(
                  l10n.emptySupport,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: NexSpacing.md),
                // The note type's own glyph, not a capture verb's: these are
                // previews of cards, and the card a text note arrives as
                // carries the text glyph.
                _Ghost('text', l10n.emptyType, onWrite),
                const SizedBox(height: NexSpacing.sm),
                _Ghost('voice', l10n.emptySpeak, onSpeak),
                const SizedBox(height: NexSpacing.sm),
                _Ghost('photo', l10n.emptyPhotograph, onPhotograph),
                const SizedBox(height: NexSpacing.md),
                Text(l10n.emptyNoSave, style: theme.textTheme.bodySmall),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  l10n.emptyAi,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on EmptyTimeline {
  Widget _clear(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: nexFabClearance + nexBottomInset(context),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.archive_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: NexSpacing.md),
              Text(
                l10n.setAsideAllClear,
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall,
              ),
              const SizedBox(height: NexSpacing.sm),
              Text(
                l10n.setAsideCountLabel(setAsideCount),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: NexSpacing.md),
              FilledButton.tonal(
                onPressed: onShowSetAside,
                child: Text(l10n.setAsideView),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An outline of the card a capture will become.
///
/// Built from the real card's tokens rather than by eye — the same radius, the
/// same inset, the same leading square at the same corner. It was drawn a
/// couple of points off on every one of those, so the shape the empty screen
/// promised was not quite the shape the first note arrived in.
///
/// In the type's own colour, as the card it becomes is — see
/// [nexNoteTypeTint].
class _Ghost extends StatelessWidget {
  const _Ghost(this.type, this.label, this.onTap);

  /// The note type's wire name.
  final String type;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(NexRadius.lg);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: _ghostBody(scheme, radius, context),
        ),
      ),
    );
  }

  Widget _ghostBody(
    ColorScheme scheme,
    BorderRadius radius,
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(NexSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(
          color: onTap == null
              ? scheme.outline
              : nexNoteTypeTint(type, scheme).withValues(alpha: 0.6),
        ),
        borderRadius: radius,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: nexNoteTypeWash(type, scheme),
              // Matches the real leading icon box — NexRadius.cardLeading.
              borderRadius: BorderRadius.circular(NexRadius.cardLeading),
            ),
            child: Icon(
              nexNoteTypeIcon(type),
              size: 18,
              color: nexNoteTypeTint(type, scheme),
            ),
          ),
          const SizedBox(width: NexSpacing.contentGap),
          Expanded(
            child: Divider(
              color: nexNoteTypeTint(type, scheme).withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: NexSpacing.contentGap),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
