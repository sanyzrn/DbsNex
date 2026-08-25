import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';

/// The one place that says what each swipe action is called and what it looks
/// like.
///
/// Both surfaces that care read from here: the timeline, which hands the spec
/// to the card so the panel can draw itself, and Settings, which lists the
/// same names and glyphs in the picker. They used to be two switch statements
/// three hundred lines apart, which was survivable at two actions and is not
/// at six.
///
/// Returns null for [SwipeAction.none] — an edge bound to nothing does not
/// move at all, which is the card's own rule.
NexSwipeActionSpec? nexSwipeSpec(AppLocalizations l10n, SwipeAction action) =>
    switch (action) {
      SwipeAction.none => null,
      SwipeAction.delete => NexSwipeActionSpec(
        action: NexSwipeAction.delete,
        label: l10n.delete,
        icon: Icons.delete_outline,
        color: NexColors.swipeDelete,
      ),
      SwipeAction.addTag => NexSwipeActionSpec(
        action: NexSwipeAction.addTag,
        label: l10n.addTag,
        icon: Icons.label_outline,
        color: NexColors.swipeAddTag,
      ),
      SwipeAction.pin => NexSwipeActionSpec(
        action: NexSwipeAction.pin,
        label: l10n.pin,
        icon: Icons.push_pin_outlined,
        color: NexColors.swipePin,
      ),
      SwipeAction.remind => NexSwipeActionSpec(
        action: NexSwipeAction.remind,
        label: l10n.remind,
        icon: Icons.notifications_none,
        color: NexColors.swipeRemind,
      ),
      SwipeAction.share => NexSwipeActionSpec(
        action: NexSwipeAction.share,
        label: l10n.share,
        icon: Icons.ios_share,
        color: NexColors.swipeShare,
      ),
      SwipeAction.ask => NexSwipeActionSpec(
        action: NexSwipeAction.ask,
        label: l10n.askAboutNote,
        icon: Icons.auto_awesome,
        color: NexColors.swipeAsk,
      ),
    };

/// What the row in Settings says under the action's name.
///
/// One short line each, because "Pin" and "Share" are obvious and "Ask" is
/// not — and a list where only some entries are explained reads as an
/// oversight rather than as restraint.
String nexSwipeActionHint(AppLocalizations l10n, SwipeAction action) =>
    switch (action) {
      SwipeAction.none => l10n.swipeNoneHint,
      SwipeAction.delete => l10n.swipeDeleteHint,
      SwipeAction.addTag => l10n.swipeAddTagHint,
      SwipeAction.pin => l10n.swipePinHint,
      SwipeAction.remind => l10n.swipeRemindHint,
      SwipeAction.share => l10n.swipeShareHint,
      SwipeAction.ask => l10n.swipeAskHint,
    };

/// The action's name on its own, for a row that is not showing a panel.
String nexSwipeActionLabel(AppLocalizations l10n, SwipeAction action) =>
    nexSwipeSpec(l10n, action)?.label ?? l10n.swipeNone;

/// The action's glyph, including the one [nexSwipeSpec] has no spec for.
IconData nexSwipeActionIcon(SwipeAction action) => switch (action) {
  SwipeAction.none => Icons.block,
  SwipeAction.delete => Icons.delete_outline,
  SwipeAction.addTag => Icons.label_outline,
  SwipeAction.pin => Icons.push_pin_outlined,
  SwipeAction.remind => Icons.notifications_none,
  SwipeAction.share => Icons.ios_share,
  SwipeAction.ask => Icons.auto_awesome,
};
