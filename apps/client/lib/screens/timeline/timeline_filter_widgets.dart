part of '../timeline_screen.dart';

/// Keeps the filter row under the app bar while the cards scroll past it.
class _FilterRowHeader extends SliverPersistentHeaderDelegate {
  const _FilterRowHeader({
    required this.child,
    required this.visible,
    required this.extent,
    this.below,
    this.lineKey,
  });

  final Widget child;

  /// Hung under the row, over the cards: the sticky day. Painted by this
  /// pinned header, which the viewport paints after the list, so it sits on
  /// top of whatever is scrolling past.
  final Widget? below;

  /// On the row's own box, so the sticky day can find where the row ends.
  final Key? lineKey;

  static const _belowHeight = 44.0;

  /// Searching hides it, by collapsing rather than by leaving the sliver list.
  final bool visible;

  // The row's own height: a 48px target plus the padding TagFilterRow carries.
  final double extent;

  @override
  double get minExtent => visible ? extent : 0;

  @override
  double get maxExtent => visible ? extent : 0;

  /// Let the page background continue beneath the resting row. Only the
  /// pinned row needs a solid backing to keep scrolled notes from showing.
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Stack(
        key: lineKey,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: _row(context, shrinkOffset, overlaps)),
          // A fixed box, so the chip's own relayout — a longer date, a
          // shorter one — stops at it. Otherwise it reached this header,
          // and a pinned header rebuilds its content whenever it relays out.
          if (below case final below?)
            Positioned(
              left: 0,
              right: 0,
              top: extent,
              height: _belowHeight,
              child: below,
            ),
        ],
      );

  Widget _row(BuildContext context, double shrinkOffset, bool overlaps) =>
      DecoratedBox(
        key: const ValueKey('filter-header-background'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: overlaps || shrinkOffset > 0
                ? [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                  ]
                : [Colors.transparent, Colors.transparent],
            stops: const [0.6, 1],
          ),
        ),
        // Filling the extent, not sized to the row. The extent is worked out
        // from the text size, and at the largest sizes the row itself stops
        // growing sooner; a header painted shorter than it lays out is an
        // invalid sliver, which took the whole timeline down.
        child: SizedBox.expand(
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      );

  /// Always, and for the same reason as [SearchFieldHeader].
  ///
  /// This one happened to rebuild anyway, because `child` is a fresh
  /// `TagFilterRow` on every build and the comparison is by identity — so it
  /// escaped the stale-theme bug by accident rather than by design. Relying on
  /// that is relying on a widget never gaining an `operator ==`.
  @override
  bool shouldRebuild(_FilterRowHeader old) => true;
}

/// What the filter sheet came back with.
///
/// Wrapped rather than returned bare so that "All" survives the trip back
/// through `Navigator.pop`, which cannot distinguish a null result from a
/// dismissal — and sealed because the sheet now answers on two axes, and a
/// switch over it is what keeps a third from being forgotten at the call
/// site.
sealed class _FilterChoice {
  const _FilterChoice();
}

class _TypeChoice extends _FilterChoice {
  const _TypeChoice(this.type);
  final NoteType? type;
}

class _ReminderChoice extends _FilterChoice {
  const _ReminderChoice({required this.only});
  final bool only;
}

/// The mockup's leading icon button on the filter row.
///
/// Carries its selected state whenever anything in the sheet behind it is
/// filtering, so an active filter is visible without opening it.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onPressed});

  /// Whether anything in the sheet is narrowing the timeline — a content
  /// type, the reminder filter, or both. A bool rather than the selection
  /// itself: what this button draws is "something is on", and it should not
  /// have to grow a parameter every time the sheet gains an axis.
  final bool active;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexTappable(
      onTap: onPressed,
      selected: active,
      semanticLabel: AppLocalizations.of(context).filters,
      shape: const StadiumBorder(),
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerLowest,
        shape: StadiumBorder(
          // Only the selected chip is outlined. The rest sat in rings that
          // did no work the fill was not already doing.
          side: active ? BorderSide(color: scheme.primary) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.contentGap - NexSpacing.xs,
            vertical: NexSpacing.sm,
          ),
          child: Icon(
            Icons.tune,
            size: 18,
            color: active ? scheme.primary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Shown when a filter matches nothing.
///
/// Distinct from [EmptyTimeline], which promises the library keeps whatever you
/// put in it — a promise that would read as a lie next to notes the filter is
/// merely hiding.
class _FilteredEmpty extends StatelessWidget {
  const _FilteredEmpty({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_list_off,
            size: 36,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          // "No notes" was a lie: the library has notes, the filters are
          // what hides them. Search already had the honest sentence; the
          // timeline's filter-empty now uses it too.
          Text(l10n.filteredEmpty, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          TextButton(onPressed: onClear, child: Text(l10n.clearFilters)),
        ],
      ),
    );
  }
}

/// The fade behind the bottom bar.
///
/// Three stops rather than two. A straight ramp from black to nothing puts
/// its colour across the middle of the band, which is exactly where the last
/// note card sits; weighting it to the bottom leaves the cards alone.
class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    final base = context.nexVisualStyle.baseColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A near-opaque page tone masks stray text under the dock but retains the
    // chosen background's hue. In light mode a black scrim looked like dirt on
    // the warm page, particularly with Comfort Mode enabled.
    final ceiling = dark ? 0.90 : 0.84;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            base.withValues(alpha: ceiling),
            base.withValues(alpha: ceiling * 0.55),
            base.withValues(alpha: ceiling * 0.18),
            base.withValues(alpha: 0),
          ],
          // Four stops let the tail disappear without a visible line across
          // a card still scrolling behind it.
          stops: const [0, 0.3, 0.62, 1],
        ),
      ),
    );
  }
}
