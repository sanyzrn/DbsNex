# Nex 2.9.0 — implementation log

Working notes for the 2.9.0 release, kept in the repository so the work can be
resumed from any machine. It is technical history, not release notes: the
user-facing copy lives in `CHANGELOG.md` / `CHANGELOG.fa.md`.

- **Base:** `main` at `d82c09c8` (merge of `release/2.8.22`, #506), fetched at
  the start of 2.9.0.
- **Branch:** `release/2.9.0`. Never merged to `main`, never force-pushed.
- **Version:** `2.9.0` in `apps/client/pubspec.yaml` and
  `apps/client/lib/app_version.dart` (single-sourced; `version_test.dart`
  guards the pair).

## The eight briefs, in the agreed order

| # | Brief | Status |
|---|---|---|
| 1 | Recurring: central early-completion window | **done — this commit** |
| 2 | One engine for Smart Summary and Daily Nudge | **done** |
| 3 | Intelligent greeting: local first, AI second | **done** |
| 4 | Keyboard / focus / input audit | **done** |
| 5 | Quick Capture: seamless code mode | **done** |
| 6 | Smart Paste / Submit button | not started |
| 7 | In-app camera: photo and video | not started |
| 8 | Android notification audit | not started |

Each brief is finished, tested, logged here, committed and pushed on its own,
and the next one waits for the owner's go-ahead.

---

## 1. Recurring — the early-completion window

### The two bugs behind the brief

1. **Chaining.** `NexCommitment.met(at)` advanced from the moment of the tap.
   Tapping the tick on a weekly item due tomorrow produced *tomorrow* again —
   so the row stayed there and could be ticked again, forever. The same was
   true of **Skip** in the ⋯ menu.
2. **No window at all.** Nothing stopped a tap weeks ahead, and `Done` in the
   notification shade, a stale row and two fast taps all took the same path
   with no shared rule.

### What the model now guarantees

`packages/core/lib/models/commitment.dart`

- `nexDefaultEarlyWindow(cadence, every)` — 10 % of the gap for hourly
  (`every * 6` minutes), 3 h daily, 24 h weekly, 3 d monthly, 7 d yearly.
- `earlyWindowMinutes` — the per-item override stored in `details`, so it
  travels through backups. `0` is a real choice: only from the due time.
- `earlyWindow` — the override or the default, **clamped to half the shortest
  real gap** (`nexMaxEarlyWindowMinutes`). That clamp is the anti-chaining
  proof: at the instant one occurrence is met the next is at least half a gap
  away, so it can never already be open.
- `completionOpensAt`, `canComplete(now)`, `isEarlyCompletion(now)`.
- `met(at)` throws `StateError` outside the window and advances from the
  occurrence (`max(at, dueAt)`), not from the tap. `complete(at)` is the null
  form for tap-driven paths; `skipped(at)` does the same for Skip.
- History records `at`, the answered `due` (the snoozed time if it was moved),
  and `early` — so "done at 18:00 for the 18:00 dose" cannot be read back as
  the 09:00 one.
- A paused item is never completable: it is not running.

### Where the rule is enforced

- **Model:** `met` refuses; `complete` returns null.
- **Storage:** `SqliteCommitmentRepository.markMet` re-reads the row, calls
  `complete`, and writes nothing when it is closed. Two taps, a stale row and
  a notification button all end here, so the second one sees the date the
  first wrote.
- **Page:** the tick is disabled (`onPressed: null`) while shut and the card
  shows a compact "Done in 3 hours" with the exact time in its tooltip. The
  page's existing one-minute clock redraws it, so the button opens by itself;
  the clock stops when the page is not visible and restarts on resume.
- **Notification:** `applyMetFromShade` already ignored a Done pressed before
  the occurrence was due; `markCommitmentMet` now refuses early ones as well,
  so a **Done** that answers a snoozed or moved alarm cannot skip a turn.
- **Skip** goes through `skipped`, so skipping the day before a weekly date
  lands on the following week rather than doing nothing.
- **Editor:** a new **Tick off early** row (Auto / a set of spans bounded by
  the clamp / "When it is due"). It is normalized against the cadence on
  screen, so switching a monthly item to hourly cannot leave an impossible
  value in the dropdown or on disk.
- **History sheet:** each entry now shows whether it was early and the turn it
  answered, beside the moment it was done.

### Deliberately unchanged

- Lead time, notification timing, the brief, the nudge, widgets and the smart
  review all read `dueAt`, whose meaning has not moved. An early completion
  does not shift the calendar anchor (`details['anchor']`), so the rhythm is
  preserved exactly as before.
- Existing rows need no migration: the override is optional and absent means
  "follow the cadence".
- Overdue items stay completable, and a skip is never blocked.

### Tests added or extended

- `packages/core/test/commitment_test.dart` — a new **the early window** group:
  defaults, the day-before boundary, the throw, one-occurrence advance, the
  next occurrence being shut, zero, the half-gap clamp, overdue vs paused,
  the monthly rhythm, snooze, and skip.
- `packages/data/test/commitment_repository_test.dart` — a write before the
  window changes nothing; inside it, one completion moves exactly one turn;
  the next one is refused.
- `apps/client/test/commitments_sheet_test.dart` — the tick is disabled with
  the "opens" line; one tap inside the window moves one week and locks again;
  the editor saves a zero window.

### Checks run in this environment

- `dart analyze` and `dart test` for `packages/core` (33 tests in the two
  commitment files) and the whole `packages/data` suite (458 passed,
  14 skipped), plus `packages/data` analyze.
- `flutter analyze` on the client: no errors introduced (the SDK used here is
  Flutter 3.50.1, which reports the repo-wide `package:flutter/material.dart`
  deprecation as info on every file; that is an environment difference, not
  this change).
- `flutter test` for `commitments_sheet_test`, `recurring_card_details_test`,
  `commitment_reminder_test`, `brief_report_test`, `daily_nudge_*`,
  `recurring_*`, `reminder_*`, `sheet_swipe_test`, `checklist_context_test`,
  `l10n_test`, `timeline_model_test` — all green.
- A 320 px card at 1.6× text was the one regression caught: a full date on the
  wrapping row overflowed. The row now shows a relative span and keeps the
  exact time in the tooltip.

### Not run here

- A real device / emulator: the minute-tick opening of the button, Android's
  shade **Done** on a moving occurrence, and RTL at large text were verified
  in widget tests only.
- `flutter build` (no Android/Windows toolchain in this sandbox).

### Remaining risks for the final audit

- `markMet` returning null is now also "the row is gone"; both callers treat it
  as "nothing moved", which is right for the page and for the shade hand-off,
  but the audit should confirm no future caller relies on a non-null result.
- The clamp uses 28-day months and 365-day years as the shortest gap. A custom
  monthly window longer than 14 days is therefore reduced; that is intended,
  but worth a sentence in the final report.

## Step 2 — one engine behind the daily brief and the daily nudge

### What changed

- **`packages/core/lib/ai/attention.dart` (new).** One reading of the
  library, `nexAttention(notes, commitments:, now:, horizon:)`, returns items
  whose *status* (`NexAttentionKind`), *urgency* (`urgent`) and *early-open
  flag* (`canCompleteEarly`, with `opensAt`) are three separate fields. The
  status is one of overdue, due today, due soon, upcoming, unfinished, idea.
  `nexAttentionKindFor` is the same classifier exposed for a caller that has a
  computed date (the nudge reads a repeating reminder at its next occurrence),
  so the rule cannot fork.
- **Facts are computed, never inferred.** Overdue means `dueAt < now` and
  unanswered; "due later today" is a kind, not a hedge. `nexAttentionLedger`
  writes the computed statuses into a block the model is told it must respect,
  and `nexAttentionContradicts` rejects a generated brief that claims nothing
  is overdue (or that nothing is left) on a library where the engine says
  otherwise. Late answers are checked against the facts they were asked from.
- **`nexBriefFacts` is now a projection of the engine** (`packages/core`).
  Same groups, same order, same fields, same note count — but the
  classification lives in one place. `brief_facts_test` passes unchanged, and
  the report style is still entirely local arithmetic.
- **The nudge (`daily_nudge_content.dart`) reads the same engine** and keeps
  its own policy on top of it: four lines, a two-day horizon, the next
  occurrence of a repeating reminder. Its pinned behaviour is unchanged (the
  "at most four facts", the ancient-note silence, the empty-library silence,
  the exact headline counts). One addition, per the brief: a note that is an
  idea rather than a task may ride along *after* real facts when capacity
  remains — it can never create a notification by itself, which would undo
  2.8.1's silence rule.
- **`digest`/`_sideBrief` (`packages/ai`) take a `statusLedger`** and carry a
  status rule in every brief prompt: never call an item due later today done,
  missed, reminded, forgotten or overdue; the ledger wins over the model's
  reading of a line.
- **The timeline header (`timeline_ai_header.dart`)** builds the ledger from the
  same notes it already hands the prompt, passes it to `digest`, rejects a
  contradicting answer before it is cached, drops an answer whose fingerprint
  no longer matches the library, clears the card when there is nothing left to
  describe, and no longer adopts a model brief written on a previous day.

### The mandatory scenario

At 10:30 on 2026-03-10, a note due 11:20 and one due 11:46 are tested three
ways: the engine (`attention_test.dart`) reports both as `due-today`, waiting,
not overdue; the plain report (`brief_report_test.dart`) prints
`📅 … today at 11:20` / `11:46` with no ⏰ and no "overdue", "missed" or
"done"; the nudge (`daily_nudge_content_test.dart`) writes "Today at 11:20"
for both, in English and Persian (Persian digits included).

### Tests added

- `packages/core/test/attention_test.dart` — the mandatory morning and its
  after-noon inverse; early-open versus not-yet-open commitments; overdue
  outranking a distant future item; urgent kept as a flag; clustering without
  merging identities; idea recency and `includeIdeas: false`; deleted and
  set-aside notes excluded from waiting; ledger contents; contradiction
  rejection and non-rejection.
- `packages/ai/test/cloud/brief_status_ledger_test.dart` — the status rule is
  in every brief prompt, the ledger travels ahead of the answer, and no empty
  placeholder heading is left when there is no ledger.
- Client additions in `daily_nudge_content_test.dart` and
  `brief_report_test.dart` as described above.

### Checks run in this environment

- `packages/core`: `dart analyze lib test` clean; full `dart test` 340 passed.
- `packages/data`: `dart analyze lib` clean; full suite 458 passed, 14 skipped
  (unchanged; `markMet` was not touched in this step).
- `packages/ai`: `dart analyze lib` clean; full `flutter test` 261 passed.
- `apps/client`: `flutter analyze` no errors or warnings introduced (the
  Flutter 3.50 `material.dart` deprecation info is environment-wide).
  `flutter test` green for `brief_report`, `brief_attention`,
  `brief_habits_visibility`, `brief_off`, `brief_refresh`, `brief_window`,
  `daily_nudge_content`, `daily_nudge_coordinator`, `daily_nudge_memories`,
  `daily_nudge_reload`, `daily_nudge`, `habits_brief_notifications`,
  `home_brief_balance`, `nudge_name`, `recap_banner`, `recap_launch`,
  `timeline_model`, `timeline_rebuild`, `timeline_noop_refresh`,
  `timeline_fold_rebuild`, `commitment_reminder`, `reminders_logic`,
  `reminder_body`.
- `dart format --set-exit-if-changed` on every touched Dart file.

### Not run here

- A real device, so no notification shade and no real clock rollover was
  observed. The midnight boundary is enforced by comparing stored dates, not
  by a timer; an app left open across midnight recomputes on the next brief
  load, and the previous day's model text is not adopted in the meantime.

### Remaining risks for the final audit

- The header's contradiction check is phrase-based on two languages; it is a
  guard rail, not a parser. A novel false wording in another language would
  pass. The ledger in the prompt is the first line of defence.
- Idea lines in the nudge are only reachable when a fact already exists, so
  the pinned silence tests still hold; if the product later wants ideas to
  open a nudge, that is a deliberate policy change and needs its own test.

## Step 3 — the greeting belongs to its moment

### What changed

- **`packages/core/lib/ai/greeting.dart` (new).** The rule, not the widget:
  `nexGreetingPartOf` (05:00 / 12:00 / 17:00 / 23:00, the boundaries the local
  phrasings were written for), `NexGreetingMoment` (local day + part +
  interface language, with a `key`), `nexGreetingBoundaries` (the next four
  instants the line can change at), and `nexGreetingFits` — one line, short
  enough for the card, in the moment's language, and naming no part of the day
  other than the current one. The night list carries the exact phrase from the
  report ("still up", «هنوز بیداری»), which is why last night's line can no
  longer pass as a morning one.
- **The cache key gained its missing half.** `ai.headline.part` is stored with
  the text, and `NexBriefRefresh.headline` only returns a cached phrase for the
  same day *and* part *and* language. A cache written before 2.9.0 has no part,
  so it is not a hit — the local greeting holds the line until the new phrase
  arrives. The in-flight request is keyed the same way: a flight for the night
  cannot answer the morning.
- **The header lives in the moment.** `_greetingPhrase` is synchronous and runs
  in build: it accepts the in-memory phrase only when its moment key matches,
  otherwise it re-reads the cache under the same three conditions. This is the
  last line of defence — no timer and no provider are needed for a stale phrase
  to be refused. The model's answer is applied only if the moment still matches
  when it lands, and an answer naming another part of the day is dropped.
- **The line changes when the clock does.** One timer is armed for the next
  boundary (and re-arms in its handler), the app's resume path checks the
  moment again, and a language change is part of the moment, so all three
  replace the line without a restart. Stale words are cleared before the
  request, so the local greeting is what is on screen in the meantime.
- **Fewer requests and fewer rebuilds.** If this moment's phrase is already on
  screen the loader returns before setting a loading flag, so a resume or a
  no-op delivery rebuilds nothing and asks nobody. The prompt now also says to
  name only the given part of the day and to avoid stock calendar lines.

### Tests added

- `packages/core/test/greeting_test.dart` — the four boundaries and the `0…23`
  edges, wire round-trip (including the absent part of an old cache), moment
  equality across day/part/language, the next boundary at 04:59, 10:00 and
  23:30, and phrase validation: right part accepted, night phrase refused in
  the morning (English and Persian), neutral phrase accepted at every hour,
  multi-line and over-long refused, wrong-language refused.
- `apps/client/test/brief_headline_moment_test.dart` — a night cache is not a
  morning hit; a current-moment cache answers without a request; a partless
  cache is not reused and is rewritten with a part; the answer is stored with
  its part; a night flight cannot answer the morning; a failure at a new moment
  never returns the old phrase.
- `apps/client/test/greeting_moment_test.dart` — on the real screen, a phrase
  cached for the current moment opens the screen, and one cached for another
  part is absent while the local greeting is already there.

### Checks run in this environment

- `packages/core`: analyze clean; full suite 350 passed (10 new).
- `packages/data`: 458 passed, 14 skipped.
- `packages/ai`: analyze clean; 261 passed.
- `apps/client`: `flutter analyze` no errors or warnings; 285 tests green across
  the 41 header/home/brief/settings/timeline files, plus the two new files
  (which also cover the AI-off path: no provider, no network, local text
  immediately).

### Not run here

- A real clock crossing a boundary, a device time-zone change and a real
  background/foreground cycle. The boundary timer is a single `Timer` cancelled
  in `dispose`; the moment is recomputed on resume and in every build.

### Remaining risks for the final audit

- The phrase validator knows two languages; a third locale's phrase is
  accepted as long as it is short and single-line. That is deliberate — an
  unknown language is not a reason to show nothing — but the time-of-day check
  only covers the English and Persian vocabularies in `_partWords`.
- A model may answer with a neutral phrase at an odd hour ("Ready when you
  are" at 03:00). It passes validation; the local phrasing is what names the
  hour, and the prompt asks the model to.

## Step 4 — the keyboard and the field being typed in

### Root cause

The report was Prompt Studio: tapping the body field opened the keyboard over
it, and the form "did not adapt". Measured rather than guessed, with a widget
that set a 320 px keyboard on a 600 px screen:

- The page's `Scaffold` *did* resize (`resizeToAvoidBottomInset` is true by
  default; the root's `false` does not reach it), so the viewport ended at
  y=280.
- The focused field was 168…364 — its lower 84 px under the keyboard.
- The reason is Flutter's own rule: it scrolls the **caret** into view, not the
  field. A six-line body field with the caret at its top is "visible" to the
  framework and still half-covered on screen.
- Scrolling the *editable text* rather than the field was not enough either: it
  left the field's label, counter and border 28 px below the keyboard. The unit
  to lift is the field's box.

### What changed

- **`apps/client/lib/widgets/focus_reveal.dart` (new).** `NexFocusReveal`
  listens to the keyboard's metrics and to focus changes, and when the keyboard
  is up scrolls the focused field — the nearest `TextField` above the focus
  node, not the inner editor — to the end of its scroll viewport
  (`keepVisibleAtEnd`), so the box is above the keyboard. It runs after the
  frame and once more on the next one, because the first pass can run while the
  scaffold is still growing (that first attempt left the box 28 px low). It
  does nothing when the keyboard is closed, and it is instant rather than
  animated: this scroll is part of the keyboard arriving, and an animation
  racing the keyboard was what left the field half-covered.
- **Installed once, above the Navigator**, in `app.dart`. Pages, dialogs and
  sheets are all inside it, so there is one rule for the app rather than a
  patch per screen.
- **`nexShowPanel` fits above the keyboard.** Its 0.88-of-the-window height is
  now measured against the window minus the keyboard, and it keeps a floor so
  a very short window does not collapse it.
- **Audited rather than assumed.** `nexShowSheet` already lifts a sheet once
  (`nex_sheet_keyboard_test`), `nexShowDialog` already pads by the inset, the
  two expenses sheets that set `resizeToAvoidBottomInset: false` live inside a
  sheet that resizes for them, and the pages carrying text fields are either a
  `Scaffold` (which resizes) or already padding by `viewInsets` by hand. The
  timeline sits directly under the root, which is deliberate: its search field
  is at the top and it hides its dock while the keyboard is up.

### Tests added

- `apps/client/test/focus_reveal_test.dart` (8) — keyboard after the tap; focus
  while the keyboard is already up (the "next field" path); a closed keyboard
  moving nothing; a dialog field; a tall field inside a sheet; a 400×520 short
  window; right to left; "remove animations".
- `apps/client/test/modules/prompt_studio/studio_widget_test.dart` — the
  reported screen itself: the real editor under the app's wrapper, the body
  field's box above a 320 px keyboard.

### Checks run in this environment

- `apps/client`: `flutter analyze` no errors or warnings introduced; the new
  files and prompt-studio editor green (248), the keyboard/input/dialog/sheet
  group green, 308 app/timeline/onboarding/desktop tests green, 1097 tests
  across the eight form-heavy module families, 899 across the other module
  families.
- `packages/core`, `packages/data`, `packages/ai` were not touched by this
  step; their suites were green in steps 2 and 3 and nothing in this change
  reaches them.

### The Android editor's frame (review follow-up)

The first version resolved the target as the nearest `TextField`, and fell
back to the focus node. On the native path there is no `TextField` in the
tree: the editor is a platform view inside an `InputDecorator` that draws the
border, the label and the counter, and the focus the platform gives the view
is *inside* that decorator. So the fallback was the text box, eight pixels of
frame were left under the keyboard, and the brief was only half met.

The target is now the field's frame itself — the nearest `InputDecorator` —
looked for both ways from the focus:

* **up**, for the Flutter editor, whose focus node sits inside the decorator
  next to the text;
* **down**, for the native editor, whose `Focus` wraps the decorator (and for
  a Dart-side `requestFocus` on a native field);
* the platform view's own node, which takes focus on a device, sits inside
  the decorator, so it is found by walking up.

`nexKeyboardRevealTarget` is exposed to tests for exactly this. The regression
test drives the native path with a mocked platform view, gives focus to the
platform view's `Focus` as Android does, opens a 300 px keyboard, and checks
the decorator's box, not the text's. With the old resolution it fails with
`frame 252..308, text 276..300`; it passes now.

### Not run here

- A real keyboard on a device and the platform's own inset animation. The
  native editor path is covered by widget tests over a mocked platform view
  (create, resize, focus); the rule itself is geometry only.

### Remaining risks for the final audit

- A screen that neither resizes (its own `resizeToAvoidBottomInset: false`)
  nor scrolls cannot be helped by a scroll: the rule would find nothing to
  scroll. None was found in this audit; a future screen that opts out of
  resizing should be checked against this.
- The reveal targets the nearest `TextField`; a custom editor that is not a
  `TextField` and not the native one falls back to the focus node's render
  object, which is the text rather than its frame.

## 5. Quick Capture — one box for every kind

### The brief

Note, checklist and link already moved between each other smoothly. Code did
not: choosing it, or leaving it, closed and reopened the keyboard and the
panel moved with it.

### Root cause

Not the field, and not the focus: the **editor was swapped**. 2.8.20 gave the
code box bracket pairs and automatic indentation through
`NexCodeInputFormatter` (`inputFormatters`), which only Flutter's editor can
run, so capture passed `useNativeEditor: !code`. Every other kind used
Android's own editor. Choosing Code therefore destroyed the platform view —
and `NexEditTextView.dispose()` hides the keyboard when the view it is
attached to goes — then the Flutter field autofocused and the keyboard came
back. Measured with the platform view mocked: **create count 1 → 2** across a
Code → Note round trip; the keyboard-height inset collapsing and returning is
what made the panel jump.

The remaining vertical movement was not the swap: it is the code tool row
above the input row (about 48 px, one row, animated) and, once, the schedule
hint line under the box.

### What changed

- **One editor for all four kinds.** Capture no longer opts out of the native
  editor: `useNativeEditor` stays true, and the editor is not rebuilt when the
  kind changes. LTR, monospace, no autocorrect, no suggestions, the language
  picker, Tab indentation and language detection are all unchanged; they were
  already native settings, not Flutter ones.
- **The code gestures moved to where the text is.** `NexTextField.code`
  travels to the native editor as a config flag, and `NexEditText` now applies
  the same two rules as `NexCodeInputFormatter`, in its own `TextWatcher` and
  *before* the change is reported: Enter keeps the current line's indent, a
  closing bracket or quote typed over its twin steps past it, and an opening
  one writes its partner with the caret between. A paste, a selection, an IME
  composition and a value from Dart are left exactly as they are. Because it
  happens inside the change, Dart and the draft see one text, never a
  correction arriving after it.
- `inputFormatters` stays for the Flutter editor, which is still what iOS and
  desktop use; nothing there changes.
- The code tool row stays **above** the input row, so the words being typed
  keep their exact place when Code is chosen; the panel grows by that one row
  and its own `AnimatedSize` covers the transition.

### Tests added

- `apps/client/test/capture_kind_switch_test.dart` (2):
  - every kind keeps one platform view (no re-create), the typed text, the
    box's height, and a box above the keyboard, with no `unfocus` sent while
    the kind changes; Code leaves the row's top exactly where it was.
  - the native config carries `code: true`, `monospace: true` and `ltr` for a
    Code box and `code: false` for a note.
  - Checked by putting the old `useNativeEditor: !code` back: the first test
    fails with `creates` 2, which is the bug.

### Checks run here

- `apps/client`: the capture/keyboard group — new test, `code_snippet_capture`
  (including the Code↔Note focus test), `capture_sheet_draft`,
  `text_keyboard_lifecycle`, `nex_text_field`, `note_editor_native_resize`,
  `capture_native_paste_focus`, `focus_reveal`, prompt-studio editor — **112
  tests, all green**; `flutter analyze` no errors or warnings.
- The Kotlin was compiled: `kotlinc 2.1.0` over `NexEditText.kt` and
  `NexMagnifierBridge.kt` against `android-36/android.jar` and Flutter's
  `flutter.jar` — no errors. An APK/Gradle build was not possible here (no
  Android SDK or Gradle in this environment).

### Not run here

- A real keyboard on an Android device: the gestures' runtime behaviour
  (pairing, stepping over a closer, indentation) and the IME staying up across
  a kind change. They are the mirror of the Dart formatter, which is covered by
  unit tests, but the Android path itself needs a device test.
