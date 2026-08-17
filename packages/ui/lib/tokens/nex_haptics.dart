import 'package:flutter/services.dart';

/// Whether the app is allowed to buzz at all.
///
/// A global rather than a parameter threaded through every widget: haptics
/// are wanted in the swipe, the pickers, the scroll and half a dozen other
/// places, and passing a flag into each of them would mean every one of those
/// widgets taking a dependency on preferences to answer a yes/no question the
/// whole app answers the same way. `app.dart` writes it whenever the setting
/// changes; nothing else does.
bool nexHapticsEnabled = true;

/// The smallest one there is: a selection moving.
///
/// For anything that changes *which* thing is chosen — a chip, a card
/// passing under the finger, a picker landing on a value. Cheap enough to
/// fire often, which is the point: a list that ticks quietly as it scrolls
/// feels attached to the finger in a way a silent one does not.
void nexTick() {
  if (nexHapticsEnabled) HapticFeedback.selectionClick();
}

/// Something happened: a note saved, a swipe committed, an action fired.
void nexBump() {
  if (nexHapticsEnabled) HapticFeedback.lightImpact();
}

/// Something that cannot be taken back, or a gesture reaching its threshold.
void nexThud() {
  if (nexHapticsEnabled) HapticFeedback.mediumImpact();
}
