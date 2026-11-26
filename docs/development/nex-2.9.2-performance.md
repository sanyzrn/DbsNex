# Nex 2.9.2 — home delete, layout switch and the IME

This is the developer record for 2.9.2. It follows
[`nex-2.9.1-performance.md`](nex-2.9.1-performance.md), and it exists because
2.9.1's three fixes — a capped capture, a deferred IME handoff and a trailing
brief pass — did not remove what the owner still felt on a device. The method
and its limits are the same: a Linux container, Flutter 3.47.9, no physical
phone, no frame profiler. What follows is structural work removed per event,
plus Dart microbenchmarks.

## 1. The brief was rebuilt on every write and every preference

**Root cause, two halves.**

`_onModelChange` arms a trailing brief pass (`_briefReload`, 250 ms) for each
notes change. That was 2.9.1's coalescing. But the timeline stream listener
also calls `_requestAiHeader(delivered)` on the same delivery, and that called
`_loadAiSummary()` immediately — whose first statement cancels `_briefReload`.
So the timer never fired: every write, including a single delete, started a
full pass on the delivery's own frame. The pass reads the habits, reads the
whole candidate library from the database, builds `nexAttention` over it and
derives the report lines. Modules never do this, which is why the identical
banner animates smoothly there and not on the home screen: the banner was
competing with a library reading, not with its own paint.

The second half is `_onBriefPreferencesChanged`. It fires for *every*
preference write — theme, card density, the list/grid switch — and it ran
`_loadAiSummary(force: changed)` in a post-frame callback unconditionally.
Switching layout therefore spent the habits read, the candidate read and the
attention engine on the frame after the switch, under the crossfade. That is
the layout lag; the crossfade was blamed for it.

**Correction.** `_requestAiHeader` no longer asks for the recap at all: the
trailing pass owns it, so a burst of writes is read once, after it settles.
The preferences listener rebuilds the brief only when the brief's own settings
changed, or when the card was just turned back on (`_daySummaryShown`); a
layout, appearance or unrelated setting rebuilds the screen and nothing else.

**Token memoization.** Even one pass re-tokenized every title. `nexAttentionTokens`
is a pure function of the text, so its answer is now memoized in a bounded
(2048-entry, insertion-ordered) cache. Measured with
`packages/core/benchmark/attention_benchmark.dart` (400 titles, x86, JIT —
indicative only):

```
attention tokens, first pass:       74,362us
attention tokens, later pass:        1,172us   (98% less)
```

The AOT figure on a phone is smaller, but the shape holds: after the first
pass, a delete or a capture re-reads one changed title rather than four
hundred.

## 2. A delete reread and rebuilt the whole timeline

**Root cause.** `deleteWithUndo` awaited `services.deleteNote`, which defaults
to `refresh: true` — a full read of the 200-note timeline window, a decode of
every note, the grouping pass, a full screen rebuild and a fresh brief pass,
all before the Undo banner was even created. A group delete did the same once
per note. This is the work that landed in the banner's entrance frames.

**Correction.** The row is committed first (`refresh: false`), the screen drops
the note from the model (`TimelineModel.removeNotes`), the tag row is re-read,
and the banner is shown immediately. One reconcile read follows unawaited: it
returns the same window the screen now holds, so `_take` suppresses its
notification and no card rebuilds under the notice. Undo still takes the full
refresh path, and a group delete performs one write per note and one local
patch instead of one library read per note.

The existing row-reuse guarantee is unchanged: the 2.8.22 row cache still keeps
untouched cards mounted (see `timeline_row_rebuild_test.dart`).

## 3. Grid rows were measured again for every new note list

`NexGridRowSizing` cached measured heights on the `Note` *instance* (an
`Expando`). Every timeline read decodes new instances, so the first grid frame
after a switch or any delivery re-laid out every visible title, preview and
caption it had already measured. Heights are now also cached by note id with
the revision and width they were measured at; a changed note misses as before,
and link art still bypasses the cache because a cover can arrive later.

## 4. The 2.9.1 pixel estimate was nine times too large for a phone

The 2.9.1 record says a 1080×2400 **logical** viewport at 3× is 23.3 M pixels
for the underlay capture. A phone with 1080×2400 *physical* pixels at 2.75× is
≈393×851 logical, so the capped 2× capture is ≈1.34 M pixels, not 23.3 M. The
cap is harmless and stays, but on the reported phone it was never the switch's
main cost — §1 was. The figure applies to a tablet-sized logical surface, not
to the device this was reported from.

## 5. Keyboard: Flutter's focus tree cannot see Android's editor

**Root cause.** 2.9.1 deferred a field's `unfocus` by 150 ms and decided at
fire time whether "a text editor holds the primary focus", by walking
Flutter's focus tree. A native field's editor is Android's `EditText`: its
focus is not reliably mirrored into that tree. When a tap moves from field A
to field B, B's editor can take the IME and report it before A reports its
loss; A's tree check can then see only A (or nothing) and hide a keyboard B is
using — the close-and-reopen, one settle window late. The same blindness had a
second failure: A's native loss handler re-requested focus for A whenever A's
Flutter node still looked primary, taking the keyboard back from the field the
person had just touched.

**Correction.** `NexImeHandoff` now keeps a registry of native editors that
report focus, separate from the tree. "Does an editor hold the keyboard" is
`hasEditors || nexFlutterTextInputHasFocus()`; a loss is skipped when another
native editor holds it, and the hide callback ignores the field that is itself
letting go. A native loss never re-requests focus while another editor holds
the keyboard. Ending a session also asks the window (not only the editor) to
hide: when the editor reported the loss that started the wait, its own
`unfocus` has nothing left to release.

The 150 ms window is still there for the one case no report can predict — a tap
that opens a sheet whose field takes focus later. Out-of-order native reports
are now handled by state rather than by luck.

## What was checked

- `packages/core`: `dart analyze` on the changed files, `dart test
  test/attention_test.dart` — 31 passing; benchmark run above.
- `apps/client`: `flutter analyze` over every changed library file and test —
  clean.
- `apps/client`: `flutter test test/nex_text_field_test.dart
  test/keyboard_dismisser_test.dart test/timeline_home_brief_work_test.dart
  --concurrency=1` — 49 passing, including the out-of-order native handoff,
  the no-reclaim case, a native editor counted without a Flutter node, and the
  new delete/layout brief-work regressions.
- `apps/client`: `flutter test test/timeline_row_rebuild_test.dart
  test/timeline_grid_test.dart test/timeline_rebuild_test.dart
  test/timeline_model_test.dart test/timeline_shelves_screen_test.dart
  test/timeline_rows_test.dart test/version_test.dart test/whats_new_test.dart
  test/brief_attention_test.dart test/brief_report_test.dart --concurrency=1`
  — 125 passing.

## Device verification still required

1. **Delete and Undo on the reported phone.** Delete from the home list, then
   from the grid, with a long list scrolled; the notice's entrance and its
   countdown should not miss frames, and the note should leave on the tap.
2. **List/grid switching**, both ways, at 120 Hz, with a library of several
   hundred notes: one switch should cost the crossfade and the grid's first
   measurement only. Confirm the first switch to grid on a large "Today" group
   is the worst case and that later switches reuse the measurements.
3. **The brief after a burst**: type several pauses into a note, then delete
   one; the card should update once, shortly after, and not during the notice.
4. **IME handoff** on a real keyboard and a third-party IME: native→native,
   native→Flutter (link dialog, search), Flutter→native; no close/reopen, no
   focus jumping back to the field that was left.
5. **A real frame trace** (`flutter run --profile`, DevTools timeline) for the
   delete and the switch, to confirm the remaining cost is paint, not a
   library read. This container cannot produce that trace.
