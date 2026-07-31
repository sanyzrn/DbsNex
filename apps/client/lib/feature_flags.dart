/// Temporary kill switch for the quick-actions bottom sheet that used to open
/// when a long press on a timeline card released without ever turning into a
/// drag — not a user preference, but a single constant a developer flips
/// back once that menu is reworked.
///
/// Drag-to-reorder itself, and pinning (now reachable from the note detail
/// sheet's action row), are unaffected — only this menu is paused, at the
/// user's request. `_showQuickActions` in `timeline_screen.dart` is
/// untouched, so setting this back to `true` is the whole re-enable.
const kReorderQuickActionsEnabled = false;
