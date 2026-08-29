import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// How tall the search field's sliver is: the field itself plus its padding.
const nexSearchHeaderExtent = nexMinTapTarget + NexSpacing.xs + NexSpacing.sm;

/// Shared [TapRegion.groupId] between the search field and its results — see
/// the field's own tap-outside handling below for why a result needs to be a
/// member of this group rather than just "not the field".
const nexSearchTapGroup = 'nex-search-tap-group';

/// The query field, living above the first card rather than on a screen of its
/// own.
///
/// It is a sliver at the very top of the timeline, and the list starts scrolled
/// past it. Pulling down brings it in — the iOS Mail arrangement — and because
/// it is genuinely part of the list rather than an overscroll effect, it
/// behaves the same under Android's clamping physics and iOS's bouncing ones.
///
/// [progress] is how far into view it has come, 0 to 1. The field fades and
/// rises with it so it arrives rather than appearing.
class SearchFieldHeader extends SliverPersistentHeaderDelegate {
  const SearchFieldHeader({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.onTap,
    required this.onChanged,
    required this.onClear,
    this.anchor,
  });

  /// Attached to the field's own box, so the first-run tour can measure where
  /// it actually is. Null everywhere the tour is not running.
  final GlobalKey? anchor;

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  // Fixed, both of them, and the header is never pinned.
  //
  // `SliverPersistentHeader` builds a different render-object subclass for
  // pinned than for scrolling, so toggling that flag swaps the object under
  // the viewport, which then paints a sliver it never laid out. Varying a
  // *pinned* delegate's extents instead fails the same way. One shape, always:
  // the field scrolls with the list, which is also what iOS Mail does — pull
  // back to the top and it is there again.
  @override
  double get minExtent => 0;

  @override
  double get maxExtent => nexSearchHeaderExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final progress = (1 - shrinkOffset / nexSearchHeaderExtent).clamp(0.0, 1.0);

    return ClipRect(
      child: Opacity(
        // Below a third of the way in there is not enough of the field on
        // screen to read, and a half-drawn control reads as a glitch.
        opacity: ((progress - 0.3) / 0.5).clamp(0.0, 1.0),
        // A tap anywhere outside the field closes search the same way the X
        // button does — the X was the only way out, so leaving search meant
        // aiming for one small target instead of just tapping whatever you
        // meant to look at. A result card shares [nexSearchTapGroup] with
        // this region precisely so tapping *it* does not count as "outside":
        // that tap fires on pointer-down, before the card's own onTap would
        // resolve, so without the group the card never got a chance to open
        // — search silently closed back to the timeline instead.
        child: TapRegion(
          groupId: nexSearchTapGroup,
          onTapOutside: (_) {
            if (searching) onClear();
          },
          // No backing behind the row. The tag row below this one needs one,
          // because it is pinned and the list genuinely runs beneath it; this
          // header is not pinned and never has anything behind it — it scrolls
          // away with the list like any other item. Painted anyway, it was a
          // band of flat colour drawn straight across whatever background the
          // reader had chosen, which is the same thing that was wrong with the
          // tag row's and is more obvious here because this strip is taller.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.md,
              NexSpacing.xs,
              NexSpacing.md,
              NexSpacing.sm,
            ),
            child: Material(
              key: anchor,
              color: scheme.surfaceContainerHighest,
              shape: StadiumBorder(
                side: BorderSide(
                  color: searching ? scheme.primary : scheme.outlineVariant,
                  width: searching ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: NexSpacing.md,
                  end: NexSpacing.sm,
                ),
                child: ConstrainedBox(
                  // One height, focused or not. The clear button only exists
                  // while searching, and it is the tallest thing in the row —
                  // so the field grew by several pixels the moment it was
                  // tapped, which read as the control jumping under the finger.
                  // This is also the tap-target floor, which the resting state
                  // was under.
                  constraints: const BoxConstraints(
                    minHeight: nexMinTapTarget,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 20,
                        color: searching
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: NexSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onTap: onTap,
                          onChanged: onChanged,
                          textInputAction: TextInputAction.search,
                          style: Theme.of(context).textTheme.bodyMedium,
                          // The caret is one of the few places the accent is
                          // spent: it means the app is listening.
                          cursorColor: scheme.primary,
                          decoration: InputDecoration(
                            isDense: true,
                            // The app's InputDecorationTheme frames, fills
                            // and pads every field, which is right for a
                            // form and wrong here: the pill around this row
                            // is already the surface, so the theme drew a
                            // second rounded box inside it with the search
                            // icon stranded outside it.
                            //
                            // Every one of these has to be named. `border`
                            // is only the fallback: `InputDecorator` paints
                            // `enabledBorder ?? border` at rest and
                            // `focusedBorder ?? border` while focused, and
                            // `applyDefaults` fills a null one from the
                            // theme — which sets both. So `border: none`
                            // alone removed nothing, and the inner box went
                            // on showing in exactly the two states the
                            // field is ever in: a soft outline at rest and
                            // an accent one under the caret, each drawn
                            // inside the pill's own matching edge.
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            hintText: l10n.searchHint,
                          ),
                        ),
                      ),
                      if (searching)
                        IconButton(
                          tooltip: l10n.clear,
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          onPressed: onClear,
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Always.
  ///
  /// This used to compare the delegate's own three fields, which is what the
  /// API invites — and it is wrong for any header that reads its colours from
  /// the theme. `shouldRebuild` gates whether the cached subtree is thrown
  /// away, and a theme change does not touch `searching`, `controller` or
  /// `focusNode`, so switching between light and dark left this header painted
  /// in the colours of the theme the app happened to launch in: a black strip
  /// across a light timeline, or a white one across a dark timeline, depending
  /// on which way you switched.
  ///
  /// A field and a row of icons is cheap to rebuild, and the state that must
  /// survive — the query and the focus — lives in the controller and the focus
  /// node, both owned outside this delegate.
  @override
  bool shouldRebuild(SearchFieldHeader old) => true;
}
