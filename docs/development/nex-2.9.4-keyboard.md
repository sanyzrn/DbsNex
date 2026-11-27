# Nex 2.9.4 — one editor, the framework's own

This is the developer record for 2.9.4's keyboard work. It follows
[`nex-2.9.3-keyboard.md`](nex-2.9.3-keyboard.md), and it closes that record's
honest ending: 2.9.3's fix was correct as far as it went, and the physical
test proved it — every transition whose source was a Flutter field came clean
— but every transition that started inside the embedded native editor still
closed and reopened the keyboard. 2.9.4 removes the cause itself: the native
Android editor is gone, and every `NexTextField` on every platform is
Flutter's own `TextField`.

The method is the same as the three records before it: code reading — the
framework's platform-view focus code included — plus widget tests that drive
the real widgets, run on the host. The device matrix that forced the decision
is 2.9.3's own result, read as a diagnosis.

## 1. The device matrix is the diagnosis

2.9.3's device verification, grouped by where the transition starts:

| Transition | Where it runs | 2.9.3 device result |
| --- | --- | --- |
| Flutter → Flutter | Price Lens product → shop → quantity; Lent & Borrowed dates → note | clean |
| Flutter → native | Gold date → notes; Habits name → note | clean |
| native → native | Prompt Studio title → body, category → notes, workbench fill fields; Family Fund forms | closing |
| native → Flutter | Habits note → name | closing |

The source of the transition decides the outcome. The Habits asymmetry makes
that legible: its Name field is a single-line Flutter `TextField` (ADR-037
never made single-line fields native) and its Note was the embedded `EditText`
— Name to note clean, note to name closing, same form, same handoff
machinery. No Dart-side coordination was ever in the path; that is why
2.9.1's deferred hide, 2.9.2's order-independent reports and 2.9.3's pure
bookkeeping each moved the failure without closing it.

## 2. Root cause: the engine's input-client switch

A `NexTextField` on Android was a virtual-display platform view
(`initSurfaceAndroidView`). An `EditText` inside a virtual display cannot take
input-method focus in its own window, so the engine serves it through the
main `FlutterView`'s single input connection, and the framework reports focus
with `TextInput.setPlatformViewClient`. That arrangement has a property no
amount of application code can change: when focus moves off such a view, the
input target must be handed from that platform-view client to the next one —
to a second `EditText`, or to a Flutter field — and the handing is done by
the engine.

The handoff passes through the engine's client switch, and on the owner's
devices the switch tears the keyboard down and brings it back. The
framework's own `_PlatformViewLinkState` clears the old view
(`_controller?.clearFocus()`) whenever its link's node loses Flutter focus,
so every transition away from a native editor delivers a second, stale loss
after the Flutter tree has moved on — the same stale loss 2.9.3 documented
and defused. Defusing the events was not enough, because the switch itself
is the close-and-reopen: it is a mechanism, not a race. 2.9.1 deferred the
hide, 2.9.2 made the reports order-independent, 2.9.3 made a loss pure
bookkeeping; all three failed because they were trying to fix a transition
that happens below the platform channel.

## 3. The design decision

### 3.1 The constraint: what the native editor was for

The native editor existed for exactly one capability, stated in ADR-037: it
laid each paragraph out in that paragraph's own first-strong direction,
against that paragraph's own start (`TEXT_DIRECTION_FIRST_STRONG` with
gravity-start), with the platform's caret, handles, magnifier and selection
menu. A stock Flutter `TextField` gives a whole field one direction; that
was the original bug — a Persian note with an English line put that line's
full stop on the wrong end, and the handles ran backwards. Everything else
the native editor carried (code gestures, the private clipboard, the
monospace face, Enter-to-send, height reporting) already had a Flutter-side
twin, and its data was always the controller's plain text.

### 3.2 The Fleather proposal, evaluated and rejected

The owner's proposed mechanism was to rebuild editing on Fleather and remove
native editors entirely. The direction was right; the mechanism was checked
against its own source (Fleather 1.28.0) and rejected on three findings:

- **It does not render per-paragraph direction at all.** Its line widget
  (`TextLine`) handles only the alignment attribute — defaulting to
  `TextAlign.left` — and no per-line `textDirection` exists anywhere in the
  package. `ParchmentAttribute.direction` exists in the document model and
  nothing renders it. It would not deliver the one capability it was
  considered for.
- **It replaces the editor everywhere.** `FleatherController` instead of
  `TextEditingController` across 48 call sites and every test; its own
  render and selection machinery instead of Flutter's handles, magnifier and
  IME behaviour; and no `inputFormatters` (the capture box's code gestures)
  and no `maxLength`.
- **Its gains do not need it.** What the migration would buy — rich text —
  is not what Nex stores: a note is plain text with markdown, applied by
  text transformations, rendered per-paragraph by the reading surfaces
  already.

### 3.3 The rejected middle: one TextField per direction run

Splitting the text into maximal runs of same-direction paragraphs — one
stock `TextField` per run — would give every paragraph its own direction and
alignment at once. It was rejected for one hard reason: a soft keyboard's
backspace at the start of a run is swallowed by the IME itself. The IME
edits the run's own field, and at its offset zero there is nothing before
the caret in that field, so Android's `deleteSurroundingText` deletes
nothing and sends nothing Dart can see. Enter merges, arrow keys and
selection would also stop at run boundaries. A dead backspace key on the
platform the app is primarily used on is not a trade worth making; saved
notes already read per-paragraph on every surface.

### 3.4 The architecture that ships

One editor, the framework's own, and the platform's rule moved to where it
is felt: **the field is laid out around the paragraph being written.** Three
pieces make it work:

1. **`nexCaretDirectionOf`** (`packages/ui/src/nex_text_direction.dart`)
   answers the direction of the paragraph a position sits in — that
   paragraph's own first strong letter, with a paragraph that carries none
   (an empty line, digits, punctuation) following the nearest paragraph
   before it that has one, then the nearest after. The stickiness is what
   keeps a new paragraph on the side the writing was on, so Enter does not
   flip the field.
2. **`NexAutoDirection`** now lays the field out around the anchor: the
   caret for a caret, and for a wider selection the end the selection is
   *from* — the end that stays put while the other one is dragged — so a
   handle dragged into a paragraph in the other language cannot relayout
   the field out from under the finger.
3. The field still **turns in place** — same element, same focus, same
   selection — when the direction actually changes, and nothing rebuilds
   otherwise. These are the original `NexAutoDirection` stability rules,
   kept: no rebuild on a selection move, a `Directionality` that is always
   present, and a rebuild that is an update, not a re-creation.

The honest limit is recorded in ADR-037's consequences: while a note with
paragraphs in both directions is being edited, the paragraphs that do not
hold the anchor sit on the anchor paragraph's side until the caret reaches
them. The paragraph being written is always correct — direction, side,
punctuation, and the selection handles resolving around that same
direction — and every reading surface lays a saved note out per paragraph,
on every platform, as it always has. Given the choice between a field that
is temporarily wrong about other paragraphs' alignment and a keyboard that
closes between fields, the keyboard is the thing people cannot work around.

## 4. What changed

| Area | Change |
| --- | --- |
| `nex_text_field.dart` | The native field, its channel protocol, the magnifier bridge and the `useNativeEditor` / `native` / `flutterMagnifier` switches are deleted. The widget is a `TextField` under `NexAutoDirection` on every platform; the public API is otherwise unchanged. |
| `nex_text_direction.dart` (packages/ui) | New `nexCaretDirectionOf`; `NexAutoDirection` resolves from the anchor's paragraph. `nexDirectionOf` and every reading surface are untouched. |
| `keyboard_dismisser.dart` | `NexImeHandoff`, its editor registry, its deferred hide and the settle window are gone — there is nothing to hand off any more. The dismisser, the guarded field, `nexDismissKeyboard` and `nexHideKeyboard` stay. |
| Android host | `NexEditText.kt`, `NexMagnifierBridge.kt`, `NexCodeGestures.kt` and their JVM test are deleted; the view factory registration and font warm-up are removed from `MainActivity`. The `nex/os_capture` hideKeyboard path stays for route teardown. |
| Call sites | The capture box keeps one editor across all four kinds, with the code gestures on `inputFormatters`; the snippet editor's `useNativeEditor` opt-out is removed. No module code changes. |
| Data | Nothing. A note is the same plain string it always was; there is no document model and no migration. |

Full reasoning in this record and ADR-037; ADR-035's deletion-proof job still
passes with the change.

## 5. Validation

Every command ran on Flutter 3.47.9 under an enforced timeout — a command
that times out counts as failed. Analyze is clean with `--fatal-infos` on
both the app and the design-system package; the format gate over the changed
files passes; the repository's Python gates (release notes, CI paths,
changed-format) pass.

| Suite | Result |
| --- | --- |
| packages/ui (design system) | 472 passing — 13 new for caret direction, anchor following, and the turn keeping editor, focus and selection |
| keyboard_dismisser + nex_text_field + note-editor resize | 40 passing — rewritten: no platform view is created at all; the keyboard is never asked to close between two `NexTextField`s or to a plain `TextField` |
| All 20 module suites | 2,072 passing |
| Top-level suites (batched) | ~2,300 passing, including the rewritten capture kind-switch, paste-focus, focus-reveal and text-selection tests |
| Performance budgets | 29 passing (tags: budget) |

The regression tests worth naming. The keyboard-continuity tests assert that
focusing a second field never sends `TextInput.hide` — the prompt-studio and
habits transitions, in the strongest form a host test can express. The
direction tests drive the caret through a two-language note and assert the
field's `textDirection` follows, in place, with the same `EditableText`
element and its focus intact. The kind-switch test holds the capture box to
one editor element across all four kinds; the note-editor test holds text and
selection through full-screen resizing; the paste-focus test holds the
editor's focus through the clipboard paste; and `text_selection_test` holds a
cross-paragraph selection through rebuilds without the field turning.

## 6. Device verification that remains

1. **The six reported flows, on the reported phone.** Prompt Studio (title →
   body → details, the workbench fill fields), Family Fund, Habits note →
   name, Gold's save sheet, and the clean pair — no close-and-reopen on any
   transition, on the stock keyboard and the third-party IME the failures
   were seen on.
2. **A mixed-direction note being written.** Persian with an English
   paragraph: the paragraph being typed in its own direction and on its own
   side; Enter keeping the new paragraph on the writing's side; the field
   turning in place when the caret crosses languages, without losing
   selection or keyboard.
3. **Stock selection UI on Android.** Handles, magnifier and the formatting
   menu in the note editor; the code gestures in a capture box (bracket
   pairing, indent carry); the private clipboard in the vault.
4. **A slow third-party IME.** With no platform-view clients left, there is
   no client switch left to race; the 2.9.1–2.9.3 reports should now be
   closed by construction rather than by timing.
5. **A hardware keyboard.** A tablet or the Windows build: the left and
   right arrows moving with the eye in both languages, Shift extending the
   selection the same way, and a plain arrow collapsing a selection to the
   side it points at.

## 7. Independent audit before merge

The release was audited as a whole before merging, including against the
editor AppFlowy builds for the same problem (appflowy-editor 6.2). Four
findings changed code; the rest of this section records what was checked and
what was deliberately left alone.

### 7.1 Arrows moved through the string, not across the screen

Flutter moves the caret in **logical** order: `arrowRight` always advances in
the string. In «سلام hello» that made the right arrow step left on screen and
the left arrow step right — the opposite of every platform text view, and of
AppFlowy, which flips the arrows per block (`arrow_left_command.dart`,
`arrow_right_command.dart`). The device matrix never covered a hardware
keyboard, so neither 2.9.3's nor 2.9.4's record saw it.

`NexVisualCaretKeys` (`apps/client/lib/widgets/nex_caret_movement.dart`)
wraps every `NexTextField` and maps the four character arrows — plain and
Shift — to a visual intent. The target is found from the laid-out text:
`RenderEditable.getLocalRectForCaret` says where a candidate sits and
`RenderEditable.getPositionForPoint` answers which character is under a
probe. It is therefore decided per run, not per paragraph: an English word
inside a Persian sentence keeps left-to-right arrows, and a Persian word in
an English note keeps right-to-left ones. Where two directions meet, a caret
has two visual positions; the one nearest the move is chosen. A plain arrow
over a selection collapses to the visual side it points at instead of
Flutter's logical end. At the edge of a line the framework's own intent
crosses the line, so vertical movement, word movement, Home/End and every
platform shortcut are untouched. AppFlowy's block-level flip is a good rule
and the right starting point; the geometry is where this goes further than
it.

The regression tests drive the real field with key events — Persian,
English, both embedded runs, Shift selection, collapse, line edges, and a
right-then-left round trip at every boundary offset
(`apps/client/test/nex_caret_movement_test.dart`). One of them also holds the
keyboard line: crossing a paragraph turns the direction without replacing
the editor, losing its focus or sending `TextInput.hide`.

### 7.2 The direction rule read the whole note on every keystroke

`nexCaretDirectionOf` built the start offset of every paragraph in the text,
searched that list, and made a substring per paragraph it considered. A
controller notifies on every keystroke **and** every frame of a selection
handle drag, so a 142k-character note paid a full scan for each one. It now
finds the two newlines around the caret, reads only that paragraph, and —
when the paragraph is neutral — walks to the nearest neighbouring paragraph
that has a direction. The field also remembers the paragraph it answered
for: while the text object is unchanged and the anchor is still inside those
bounds, a selection move is answered without reading anything. Measured on
the host JIT, 2,000 scans at the end of a 142k-character note: **138.2 µs per
scan before, 1.9–3.0 µs after** (0.9 µs mid-note, uncached), roughly 45–70×
depending on what else the machine is doing.
`packages/ui/benchmark/nex_direction_benchmark.dart` keeps the measurement.
The bounds are part of the public rule as `nexCaretParagraphOf`, so the
cache is checked against the same paragraph the field would resolve.

### 7.3 Scripts outside the Arabic and Hebrew blocks had no direction

First-strong covered the Arabic and Hebrew blocks, their presentation forms
and the common left-to-right ranges. Adlam, Yezidi, Phoenician, Imperial
Aramaic, Old South Arabian, Old Hungarian and the other right-to-left
supplementary scripts answered *null* — "no direction" — so a note opening
in one inherited the interface's direction. Their script ranges are now
listed explicitly, and the left-to-right scripts that share those planes
(Cypriot, Linear B, Deseret) are held out.
`nex_caret_paragraph_test.dart` covers both halves.

### 7.4 Leftovers from removing the native editor

The native editor's Dart-side formatting helpers (`nexFormatCommands`,
`nexApplyFormat`) had no callers left; they are gone. Comments and live docs
that still said multi-line text is edited in Android's own editor were
corrected (`docs/05-design.md`, `test/text_field_rule_test.dart`, the chat
composer, the capture sheet, the keyboard dismisser, the Words and Gold
notes), and ADR-042's loupe is marked withdrawn with the editor it magnified.

### 7.5 Selection handles and the magnifier

No custom selection UI was reintroduced. Flutter's handles, lens and menu
are the ones in use. The magnifier is stated explicitly as
`TextMagnifier.adaptiveMagnifierConfiguration` in `NexTextField` so a later
edit cannot disable it silently, and a test holds it there. What makes the
handles draw on the right ends is `NexAutoDirection`'s `Directionality`: the
framework resolves handle sides against the ambient direction, which is what
the direction work supplies. The existing test that the field owns that
`Directionality` remains the handle-orientation test; the new one adds the
lens.

### 7.6 What was deliberately not done

A single Flutter `TextField` still cannot lay out two paragraphs in two base
directions at once. AppFlowy can, because its document is a tree of blocks
and each block owns its own text layout and selection; that is a different
product architecture, and §3.2–3.3 record why replacing the editor with one
(and with Fleather, its Flutter sibling) was rejected: no per-paragraph
rendering in the package, a replacement of every controller and every
selection behaviour, no input formatters or `maxLength`, and — for the
per-run `TextField` middle ground — a dead backspace at a run boundary.
What ships is the honest limit already in ADR-037: the paragraph being
written is always right; the others sit on its side until the caret reaches
them; every reading surface keeps per-paragraph layout. The audit did not
change that trade, and it did not reintroduce a native editor to get around
it.

### 7.7 Validation of the audit

Commands ran on Flutter 3.47.9, host JIT, with the repository's analysers at
`--fatal-infos` and the format gate over every changed file.

| Check | Result |
| --- | --- |
| `packages/ui` analysis | clean |
| `apps/client` analysis | clean |
| `packages/ui` tests (full) | 479 passing — includes 7 new caret-paragraph and script tests |
| `nex_caret_movement_test.dart` | 9 passing — arrows, Shift, collapse, edges, round trip, keyboard continuity |
| `nex_text_field` + `keyboard_dismisser` | passing — including the new lens assertion |
| App suite (full) | 4,942 passing, 7 skipped |
| Direction benchmark | 142k characters, 2,000 scans: 138.2 µs → 2–3 µs per caret scan |

The host used for the audit ships `libsqlite3.so.0` but not the unversioned
`libsqlite3.so` the test harness loads, so the app suite ran with
`LD_LIBRARY_PATH` pointing at a symlink to the system library. That is a
host detail, not a test change; nothing was skipped or weakened for it. The
device checks in §6 remain device checks. Nothing here claims the arrow keys
or the lens were seen on the owner's phone; the tests drive the real widgets
on the host, which is the strongest evidence available in CI.
