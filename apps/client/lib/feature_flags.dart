/// Temporary kill switch for a shipped-but-paused feature — not a user
/// preference, but a single constant a developer flips back once the
/// feature is ready again.
///
/// Covers long-press-to-reorder on a timeline card, the quick-actions menu
/// that opens instead when it is released without moving, and the pin
/// capability that surfaced through both that menu and the note detail
/// sheet. Paused at the user's request while it's reworked; every piece
/// behind it — `SwipeableNoteCard`'s reorder support, the repository's
/// pin/reorder methods, `Note.pinnedAt`/`sortOrder`, the pinned-first sort in
/// `listTimeline` — is untouched, so setting this back to `true` is the
/// whole re-enable.
const kPinAndReorderEnabled = false;
