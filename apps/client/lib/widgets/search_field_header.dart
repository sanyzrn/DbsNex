import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// How tall the search field's sliver is: the field itself plus its padding.
const nexSearchHeaderExtent =
    nexMinTapTarget + NexSpacing.xs + NexSpacing.sm;

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
  });

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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final progress =
        (1 - shrinkOffset / nexSearchHeaderExtent).clamp(0.0, 1.0);

    return ClipRect(
      child: Opacity(
        // Below a third of the way in there is not enough of the field on
        // screen to read, and a half-drawn control reads as a glitch.
        opacity: ((progress - 0.3) / 0.5).clamp(0.0, 1.0),
        child: ColoredBox(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.md,
              NexSpacing.xs,
              NexSpacing.md,
              NexSpacing.sm,
            ),
            child: Material(
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
                  constraints: const BoxConstraints(minHeight: nexMinTapTarget),
                  child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 20,
                      color: searching ? scheme.primary : scheme.onSurfaceVariant,
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
                          border: InputBorder.none,
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

  @override
  bool shouldRebuild(SearchFieldHeader old) =>
      old.searching != searching ||
      old.controller != controller ||
      old.focusNode != focusNode;
}
