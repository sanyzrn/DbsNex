import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';

class EmptyTimeline extends StatelessWidget {
  const EmptyTimeline({
    super.key,
    this.onWrite,
    this.onSpeak,
    this.onPhotograph,
  });

  /// What each example row does when tapped: the first note, started from
  /// the row that describes it (1.94.0). An empty library used to only
  /// explain itself; the capture button was the one way in.
  final VoidCallback? onWrite;
  final VoidCallback? onSpeak;
  final VoidCallback? onPhotograph;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
                _Ghost(nexNoteTypeIcon('text'), l10n.emptyType, onWrite),
                const SizedBox(height: NexSpacing.sm),
                _Ghost(nexNoteTypeIcon('voice'), l10n.emptySpeak, onSpeak),
                const SizedBox(height: NexSpacing.sm),
                _Ghost(
                  nexNoteTypeIcon('photo'),
                  l10n.emptyPhotograph,
                  onPhotograph,
                ),
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

/// An outline of the card a capture will become.
///
/// Built from the real card's tokens rather than by eye — the same radius, the
/// same inset, the same leading square at the same corner. It was drawn a
/// couple of points off on every one of those, so the shape the empty screen
/// promised was not quite the shape the first note arrived in.
class _Ghost extends StatelessWidget {
  const _Ghost(this.icon, this.label, this.onTap);
  final IconData icon;
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
          color: onTap == null ? scheme.outline : scheme.primary,
        ),
        borderRadius: radius,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              // Matches the real leading icon box — NexRadius.cardLeading.
              borderRadius: BorderRadius.circular(NexRadius.cardLeading),
            ),
            child: Icon(icon),
          ),
          const SizedBox(width: NexSpacing.contentGap),
          Expanded(
            child: Divider(color: scheme.secondary.withValues(alpha: 0.3)),
          ),
          const SizedBox(width: NexSpacing.contentGap),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
