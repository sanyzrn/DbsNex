# Nex 2.9.1 — performance, keyboard and Markdown

This is the developer record for 2.9.1: what was wrong, what changed, what was
measured, and what still needs a device. It is deliberately separate from the
user-facing changelogs, which say only what a reader notices.

## Method and its limits

The work was done in a Linux CI-like container with Flutter 3.47.9 (the
version pinned by `.fvmrc`). There is no physical Android device, no 120 Hz
panel and no Impeller/Skia frame profiler in that environment, so:

- the layout and notification measurements below are structural (work removed
  per event, pixels copied, timers armed) plus a Dart microbenchmark for the
  pure attention code;
- widget tests assert behaviour (directions, focus calls, timers), not frame
  times;
- the device checks that remain are listed at the end and must be run before
  the release is called verified on hardware.

## 1. List/Grid switching: the old view was copied at full resolution

**Root cause.** `_ViewDissolve.capture` calls `_RenderLastFrame.lastFrame`,
which calls `OffsetLayer.toImageSync` on the whole timeline viewport. It runs
synchronously from `_fadeOnViewChange` on the frame of the tap that changes
arrangement, density, type or filters — the exact frame the user is waiting on.
At a 3x device pixel ratio and a 1080×2400 logical viewport that is a
3240×7200 (≈23.3 M pixel) copy, plus the GPU readback that `toImageSync`
implies. A mid-range phone cannot do that inside a 120 Hz budget.

**Correction.** The transient underlay is captured at
`min(devicePixelRatio, 2.0)` (`_ViewDissolve.maxPixelRatio`). The picture is
only drawn under a fade of ≤ 300 ms with `FilterQuality.low`, so 2x is above
what that fade can show.

Measured pixel counts for the same viewport:

| Device ratio | Before            | After             | Pixels removed |
| ------------ | ----------------- | ----------------- | -------------- |
| 3.0x         | 3240×7200 ≈ 23.3 M | 2160×4800 ≈ 10.4 M | 55%            |
| 2.75x        | 2970×6600 ≈ 19.6 M | 2160×4800 ≈ 10.4 M | 47%            |
| 2.0x         | 2160×4800         | 2160×4800          | 0%             |

The crossfade, its timing, its clipping below the filter row and the painter
are unchanged; only the resolution of the temporary image is capped.

## 2. Notifications: a 100 ms timer for the whole lifetime

**Root cause.** Each visible banner ran `_tickLife`, a chain of 100 ms timers
that woke the isolate ten times a second for as long as the banner lived
(2.2–6.5 s normally, plus 2 s for an actionable one). That is 22–85 timer
callbacks per banner, competing with the entrance/exit animation and with any
list work around a delete. The pause-on-hold feature is why the countdown had
been written as slices: a one-shot timer cannot report how much of itself has
elapsed.

**Correction.** One `Timer` is armed for the exact remaining lifetime. A
`Stopwatch` runs alongside it and is read only when a finger holds the banner;
pausing computes the remainder and cancels the timer, resuming re-arms it.
A banner that is never held now costs exactly one timer callback instead of
tens.

The delete path also no longer starts a brief pass on the frame that shows the
Undo: see §3 (a write-triggered pass is trailing by 250 ms).

**Follow-up: what the animation itself costs.** The timer was idle work; it was
not what animates the entrance and exit. Auditing the rest:

- the page below is inside a route `RepaintBoundary`, so the banner's motion
  does not repaint the list;
- the gooey pass is bounded to roughly the capsule plus the drip area — never
  the screen — and is the only part of the banner that creates offscreen
  layers (two `saveLayer`s plus a blurred mask pass);
- the shadow (`drawShadow`) is painted only at rest (`t == 1`), once, not on
  every frame of the transition;
- the gooey ran for the whole 360 ms entrance and 300 ms exit, even after the
  island and the thread had shrunk to nothing at 60% of the film. With a
  single shape left, the blur-and-threshold pass produces that same shape
  with a softer edge; the painter now draws the capsule directly from
  `t >= 0.6`. That takes the last 40% of both transitions off the GPU without
  changing the resting or moving capsule's geometry, colour or shadow.

What remains is the first 60% of the entrance/exit: two bounded offscreen
layers, a blur over the drop/thread/island, and the content's opacity layer.
That is the effect as designed; removing it would change the visual identity.
It is small (the layer is below 0.1 MP at a 1x scale, around 0.7 MP per layer
at 3x) and short, and the device check remains the way to confirm its frame
time.

## 3. The brief was reread for every write

**Root cause.** `_onModelChange` called `_loadAiSummary()` on every
`TimelineChange.notes` and `TimelineChange.commitments`. Each pass awaits the
habits, reads the whole candidate library (`briefCandidates`), reads semantic
pairs, builds `nexAttention` and the ledger, and only at the end asks the
refresh policy whether anything it cares about moved. An in-flight guard
prevented overlapping passes, but a burst of writes (typing in a note, a batch
delete, an import) produced one full pass per write once the previous one
finished.

**Correction.** A notes/commitments notification now schedules one trailing
pass 250 ms after the last write (`_briefReload`); any pass that starts
cancels the queued one, and the timer is cancelled with the screen. A manual
pull still runs immediately and is unaffected. The `canPersist` re-read is
kept on purpose: it is the check that the library did not change while the
model was answering, one read per response rather than per frame.

## 4. Attention engine: patterns and folding

**Root cause.** `nexAttentionTokens` compiled its Unicode word pattern on
every call; `_clocksIn` and `_countClaims` compiled their patterns for every
line of a generated brief; `_anyIn` folded every constant needle again for
every line.

**Correction.** The three patterns are compiled once at top level. Folded
needles are memoized (`_foldedNeedles`), which is safe because every needle
comes from a constant list.

**Benchmark.** `packages/core/benchmark/attention_benchmark.dart` compares
the 2.9.0 shape with the 2.9.1 shape on the same inputs (400 titles, 80 brief
lines; x86 container, indicative only):

```
attention tokens: 75013us -> 74408us (1% less)
any needle:       169320us -> 93262us (45% less)
```

The needle scan is the material one. The token pattern hoist measured within
noise on this host (Dart caches identical compiled patterns internally) and is
kept as an allocation cleanup, not as a claimed speedup.

## 5. Markdown: one direction per block

**Root cause.** `NexMarkdown` wrapped the whole document in one
`Directionality`, decided by `nexDirectionOf` — the first strong character.
A Persian note beginning with an English product name therefore laid the whole
document out left to right.

**Correction.** `nexDominantDirectionOf` counts strong letters and returns the
script with the majority; ties fall back to the first strong letter.
`nexDirectionOf` is untouched (editors and existing tests depend on the
first-strong rule). `NexMarkdown` now wraps every block's inline runs in a
synthetic `nex-text` element and builds those runs itself, under a
`Directionality` of their own; the package keeps the block structure —
paragraph padding, list bullets, nested lists, blockquote rule, table cell,
borders and column sizing. Fenced code remains LTR in its own builder.

Two package constraints shaped this design, and both were found by tests:

- overriding `li` or `blockquote` replaces the block widget and drops the
  nested blocks the renderer had already built inside it (nested lists lost
  their structure; multi-paragraph quotes lost their paragraphs);
- overriding `th`/`td` is an inline branch that never creates the `TableCell`,
  leaving an empty `TableRow` and a `Table` assertion.

Wrapping the inline runs leaves the package's block work intact and puts the
direction exactly where the text is. A table cell's explicit `align` still
wins over its direction; untagged cells align to their own start edge.

**Cost.** `packages/ui/benchmark/nex_direction_benchmark.dart` (`flutter test benchmark/nex_direction_benchmark.dart`) over a 266k-character
bilingual document: `nexDirectionOf` ≈ 0.000 ms/scan (it stops at the first
strong letter), `nexDominantDirectionOf` 2.587 ms/scan. The count is linear
and runs once per parse, on the same pass that lays the document out; a
5k-character note is ≈ 0.05 ms, and each block scans only its own words.
There is no per-frame work and no extra rebuild.

Regression coverage is `packages/ui/test/nex_markdown_direction_test.dart`
(Persian-only, English-only, mixed, English-leading Persian, Persian-leading
English, nested lists, task lists, blockquotes, mixed tables, explicit cell
alignment, inline and fenced code, URLs, digits, punctuation, formatting and
line breaks, fa and en interface locales, and the unchanged
`nexDirectionOf`). The existing `nex_markdown_test.dart` tap tests drove the
`Align` rather than full-width `Text` layout: a full-width text answered taps
in the empty half beside short RTL lines.

## 6. Keyboard: handing the IME over instead of closing it

**Root cause.** On Android, `_NativeFieldState._onFocus` sent `unfocus` to the
native editor as soon as its focus node lost focus. `NexEditText.unfocus`
hides the IME immediately. When a tap moves between two fields on the same
screen, the old field loses focus and the new one gains it in the same frame:
the hide and the new field's `focus` race, so the keyboard closes and reopens
and the layout jumps.

**Correction.** `NexImeHandoff` (in `keyboard_dismisser.dart`) defers the hide
by 150 ms. Any field gaining focus — native `focus` true, or a Dart
`requestFocus` — cancels the pending hide, so nothing is sent and the keyboard
never leaves. If nothing takes over, the hide still happens one handoff later,
which is below the threshold at which the closing is noticeable. A field
cancels its own pending hide on dispose, so a sheet closing cannot leave a
timer behind that hides a keyboard someone else is using. `nexDismissKeyboard`
(route teardown) cancels any pending handoff and hides immediately.

**Follow-up: order independence.** A timer cancelled only by a *gain* has a
hole: if the old field's loss notification is delivered after the next field
has already taken focus, the gain has happened and cannot cancel a hide that
is scheduled afterwards. `lose()` therefore asks the focus tree whether a
text editor holds focus before scheduling, and asks again when the timer
fires (`nexTextInputHasFocus`; a focus node under `EditableText`, or under the
`TextFieldTapRegion` of a native field). This also covers a field that gains
focus during the settle window, and it is current at the moment it is read
rather than a frame behind. The 150 ms is still needed for one case no focus
event can predict: a tap that opens a sheet or dialog whose field requests
focus later than the settle window. There the keyboard is hidden and reopened
by that field — the same thing that would happen if the handoff guessed it was
coming.

The controller, selection, native editing, `NexKeyboardDismisser` and
`NexFocusReveal` are untouched; the change is only when `unfocus` is sent.

## Tests run for this change

- `packages/ui`: `flutter test test/nex_markdown_direction_test.dart
  test/nex_markdown_test.dart test/nex_text_direction_test.dart` — 57 passing
  (Flutter 3.47.9).
- `apps/client`: `flutter test test/nex_text_field_test.dart
  test/keyboard_dismisser_test.dart` — 43 passing, including the two-field
  handoff and the Flutter-field ordering regressions.
- `apps/client`: `flutter test test/nex_banner_test.dart` — 15 passing with
  the single-timer countdown.
- `apps/client`: `flutter test test/capture_kind_switch_test.dart` — 2
  passing (run with a local `libsqlite3.so` symlink; see below).
- `packages/core`: `dart test test/attention_test.dart` — 31 passing.
- `apps/client`: `flutter test test/version_test.dart
  test/brief_attention_test.dart test/timeline_row_rebuild_test.dart` — 14
  passing.
- `packages/core`: `dart analyze benchmark/attention_benchmark.dart`,
  `dart run benchmark/attention_benchmark.dart`.
- `packages/ui`: `flutter test benchmark/nex_direction_benchmark.dart` (a
  benchmark that prints its numbers and asserts nothing about them).

The container only ships `libsqlite3.so.0`; tests that open the database need
the unversioned `libsqlite3.so`. They were run with
`LD_LIBRARY_PATH=/tmp/libsqlite`, where that name is a symlink to the system
library. This is an environment workaround, not a project change.

## Device verification that is still required

1. **Android IME handoff.** Focus two fields in a form, a dialog and the note
   editor in sequence, on a real keyboard: no close/reopen, no content jump.
   Check a slow mid-range device and a device with a third-party IME. The
   150 ms window is a heuristic; a field that takes longer than that to gain
   focus will still see one close/reopen.
2. **List/grid switching at 120 Hz.** Frame timing with the devtools overlay
   on a mid-range phone: the capture is cheaper but still runs on the tap
   frame; confirm no missed frame and that the 2x underlay is not visibly
   softer at the end of the fade.
3. **Undo banner.** Delete a note and dismiss the banner while a long list is
   scrolling; confirm the countdown and the exit animation do not contend
   with list work, and that the 250 ms brief delay does not feel like a stale
   summary after a delete.
4. **Markdown visuals.** Widget tests prove the direction and styles of the
   spans; open a mixed Persian/English note, a file preview, an assistant
   answer, a caption and a table in both fa and en locales and check glyph
   rendering, selection and copy across block boundaries on a device.
5. **Benchmark on hardware.** The attention numbers above are x86; run the
   same benchmark on an ARM device if a regression of the brief's local work
   is suspected.
