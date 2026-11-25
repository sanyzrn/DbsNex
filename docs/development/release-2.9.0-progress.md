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
| 6 | Smart Paste / Submit button | **done** |
| 7 | In-app camera: photo and video | **done** |
| 8 | Android notification audit | **done** |

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
  *before* the change is reported: Enter keeps the current line's indent (and
  its Windows line ending), a closing bracket or quote typed over its twin
  steps past it, and an opening one writes its partner with the caret between.
  A paste, a selection and a value from Dart are left exactly as they are.
  Because it happens inside the change, Dart and the draft see one text, never
  a correction arriving after it.
- **Real keyboards.** A soft keyboard keeps the word being typed in an IME
  *composing span*; refusing to act whenever one is open would have made the
  gestures silently never fire on a device. They now act on any single typed
  character and remove the composition afterwards, committing the word to the
  field — keeping spans that no longer match the text would leave the keyboard
  writing into a stale document. Multi-character input (autocorrect, paste,
  a composed word) still fails the one-character test and is left alone.
- `inputFormatters` stays for the Flutter editor, which is still what iOS and
  desktop use; nothing there changes.
- The code tool row stays **above** the input row, so the words being typed
  keep their exact place when Code is chosen; the panel grows by that one row
  and its own `AnimatedSize` covers the transition.

### Tests added

- `apps/client/android/app/src/test/java/com/sanyzrn/nex/NexCodeGesturesTest.kt`
  (8 JVM tests): the gesture rule itself, now a pure function
  (`NexCodeGestures.kt`, no Android classes) so it can be checked without a
  device — indentation (spaces, tabs, CRLF), pairing for every bracket and
  quote, the quote-after-word and escaped-quote refusals, stepping over a
  closer, and the cases that must do nothing (paste, selection, ordinary
  letter, a change from Dart).
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

### How to validate the Android half

- **On a build machine:** `cd apps/client/android && ./gradlew testDebugUnitTest`
  runs `NexCodeGesturesTest` next to the existing `NexCycleTodayTest`. The
  same file can be compiled and run without Gradle:
  `kotlinc NexCodeGestures.kt NexCodeGesturesTest.kt -classpath junit.jar:hamcrest.jar`
  then `java -cp … org.junit.runner.JUnitCore com.sanyzrn.nex.NexCodeGesturesTest`.
  In this environment that ran 8 tests green, and `NexEditText.kt` +
  `NexMagnifierBridge.kt` + `NexCodeGestures.kt` compiled with `kotlinc 2.1.0`
  against `android-36/android.jar` and Flutter's `flutter.jar` with no errors.
- **On a device** (still needed: the IME, the platform view and the keyboard's
  own behaviour are not in a JVM test):
  1. In the capture box, choose Code; the keyboard must stay up (no blink) and
     the text must not move.
  2. Type `if (x)` in a line indented by two spaces, press Enter: the new line
     is indented two spaces.
  3. Type `(`, `[`, `{`, `"` and `'`: the partner appears and the caret stays
     between the two.
  4. Type a closing `)` when one is already next: the caret steps past it and
     no second `)` is written.
  5. Paste multi-line code: it lands unchanged (no pairing, no indentation
     rewriting).
  6. Switch Note → Code → Note → Checklist → Link with the keyboard up: the
     keyboard never closes, the words stay, and the panel does not jump by the
     keyboard's height.
  7. With a Gboard/Persian keyboard, repeat 2–3: the composition must not
     swallow the pair or duplicate the character.


## 6. The capture box — Paste in the primary button

### The brief

Take the Paste icon out of the field, give the words the whole width, and let
the main button be Paste when the box is empty and the clipboard holds
something the kind can take — otherwise Send, exactly as before. Pressing
Paste inserts and never sends.

### What changed

- **The in-field slot is gone.** `_CapturePasteSlot` (Paste, and Clear in a
  link box) is deleted; the field is the whole row. Clear had existed because
  a one-line link field left select-all nowhere to live; with the slot gone
  the field has its width back, and Paste is one tap away whenever the box is
  empty.
- **One primary button, two jobs.** `_SendButton` takes `paste` and
  `onPaste`. When the box is empty, the clipboard has text, and — for a link
  box — that text is an address, it shows the paste glyph, is labelled Paste
  for screen readers, and inserts. In every other state it is Send (or the
  note glyph in a link box holding words that are not an address), including
  the moment after a paste or the first keystroke. The button's box is fixed
  at 60×60, so nothing in the row moves; paste enters with a fade and a small
  scale rather than the arrow's turn.
- **Asking the clipboard without reading it.** `Clipboard.hasStrings` decides
  whether there is anything to paste — it reads only the clip's description,
  so Android shows no paste notice. The words themselves are read **only for
  a link box**, where "pasteable" means "an address", and only at the moments
  it matters: opening the sheet, coming back to the app, entering a link box,
  and emptying the box. No timer, no read per frame, no logging.
- **Late and repeated answers.** A check carries a generation number; an
  answer that a kind switch or a resumed app has made stale cannot move the
  button. A second tap while the clipboard is being read cannot insert twice.
- **Two existing bugs found on the way.** `changed()` now re-checks the
  clipboard on the typing→empty flip, which is what makes a cleared box offer
  Paste again. And with reduced motion, a zero-length `AnimatedSize` in the
  composer (and in its footnote) re-dirtied itself inside its own layout —
  Flutter's assertion, in debug — so both now sit behind `_ComposerSize`,
  which skips the animation entirely at zero duration.

### Insertion, per kind

Unchanged from before: a note or checklist takes the words verbatim, a link
box trims them, and an address pasted into an **empty note** still turns the
box into a link (only the Paste button guesses that; words pasted beside an
address stay a note). Code takes the text as it is. Nothing here sends.

### Tests

- `apps/client/test/capture_paste_button_test.dart` (8):
  - an empty box offers Paste; pressing it inserts, leaves the sheet open,
    keeps the words as the note typing would have made, and turns the button
    back into Send;
  - typing hides Paste; clearing asks again and brings it back;
  - an empty clipboard leaves Send;
  - a link box offers Paste only for an address, and notices the clipboard
    changing while the sheet is open;
  - a checklist takes any words, without reading them;
  - two quick taps insert once;
  - a late clipboard answer cannot undo a newer one;
  - with reduced motion the button keeps its exact size through the swap.
- Adapted, not weakened: `capture_paste_link_test` (button glyph instead of
  the old Clear slot; the pasted-into-a-note case now checks the saved note's
  type), `capture_native_paste_focus_test` (the new button keeps the native
  editor's child focus and sends no focus calls), `checklist_link_capture_test`
  (the field's width on a 320 px phone; the Clear test became the link box's
  Paste-only-for-an-address test).
- Run here: those four files plus the capture and keyboard group —
  `capture_sheet_draft`, `code_snippet_capture`, `capture_kind_switch`,
  `text_keyboard_lifecycle` — **87 tests green**; `flutter analyze` clean.

### Not run here

- A real device's clipboard: the system's own paste notice on Android 12+,
  the behaviour of `hasStrings` with a clipboard owned by another profile, and
  TalkBack reading the button's changing label. The privacy design deliberately
  reads the words only in a link box; that one read per link-capture is the
  price of not offering Paste for a line of prose.

## 7. The camera — a hold records, a tap photographs

### The brief

One panel shared by initial capture and note attachments: tap the shutter for
a photo; hold it to record video with sound; let go and the result goes to the
path that opened the camera. Recording state, elapsed time and feedback have
to be clear, a stray photo must never follow a recording, and places that only
take pictures (a profile picture, a vault document) must stay that way.

### The root of it

The panel was built around `takePicture` alone: the controller asked for no
audio (`enableAudio: false`), the shutter had a single `onTap`, and the one
door everyone used — `nexTakePhoto` — returned an `XFile` with no way to say
"this is a video". The timeline wrapped whatever came back in a
`CapturedMedia` whose kind defaulted to *image*, so a recording could only ever
have reached the library as a broken photo.

### What changed

- **One door, with a kind.** `NexCameraShot` carries a file and whether it is a
  recording. `nexTakeShot(context, video: true)` opens the panel with the video
  gesture; `nexTakePhoto` stays as the still-only door for the places that
  should not record, so the profile picture, a vault photo and a Recurring
  receipt keep the panel (and the system camera fallback) they had.
- **The gesture.** The shutter is a raw `Listener`, not a long-press
  recogniser: 280 ms of rest starts a recording, lifting before that is a
  photo, and lifting after it stops the recording. A tap can never become a
  hold and a hold can never leave a photo behind, because the same pointer
  decides one or the other once.
- **Releasing before the sensor answers.** `startVideoRecording` is async; a
  lift while it is in flight sets `_stopRequested`, and the recording is
  stopped the instant it begins. The file is then too short to keep and is
  deleted, so a quick double-tap leaves neither a stuck shutter nor a clip.
- **What is kept.** The panel keeps anything from 900 ms; shorter holds are
  deleted and answered with "Hold a little longer to record". Three minutes is
  the ceiling: the ticker stops a held-open shutter itself, and 1080p for
  video keeps that comfortably inside the 500 MiB attachment limit. Photos are
  still taken at the sensor's largest size.
- **Sound, without taxing stills.** A still-only panel never asks for the
  microphone. A video panel asks during initialisation; if the microphone is
  refused it reopens the camera without audio and says "Recording without
  sound" in the badge — the camera keeps working, the person is told why the
  video will be silent.
- **Never the wrong result.** While recording, the shutter turns into a red
  stop square (still a button, so stopping is not only a gesture), the ⋮ menu
  becomes a stop button, and the clock pill runs at the top. Closing the panel
  stops and discards the recording; sending the app to the background stops
  and keeps it, so a phone call cannot swallow a recording in progress.
  Photos taken during `_taking` or a recording are ignored, and launching a
  recording while a photo is being saved is ignored too.
- **Reaching the library properly.** The timeline marks the shot's kind, so a
  recording goes through the existing `captureFile` path (video note, player,
  thumbnail) rather than the photo path; camera videos are size-checked like
  gallery ones. In a note's attachments a recording is attached as a video
  file, so the strip shows its frame and opens its player; a photo remains a
  photo attachment. Photo editing and its drafts are still only ever applied
  to stills.
- **Words.** The attach sheet's "Take a photo" is now **Camera** in both
  languages, the hint and the recording clock are localized, and the screen
  reader hears the hold hint on the shutter and the elapsed time as a live
  region. Reduce-motion turns the blinking dot still.
- **The system camera.** On a phone the fallback asks for a video when the
  panel could not open; on a desktop, where the camera app is a photo camera,
  it stays a photo.

### Tests

- `test/camera_recording_test.dart` (3): the clock pads and keeps counting
  past an hour, the shortest kept video is below the three-minute ceiling, and
  the hold threshold is shorter than the shortest kept video.
- `test/camera_sheet_test.dart` (9, one new): the video panel shows the hold
  hint and speaks it with the shutter; the still-only panel shows neither.
- `photo_capture_policy_test` (8, unchanged) covers camera and gallery through
  the timeline; `attachments_test`, `media_selection_test`,
  `video_preview_test`, `profile_photo_test` and the capture/keyboard group
  were run alongside — **108 tests green** — and `flutter analyze` reports no
  errors or warnings.

### Not run here

- Anything that needs a sensor: `startVideoRecording`, audio in the file,
  switching lens mid-recording, the real microphone permission dialog, the
  camera being taken by another app, and the panel's behaviour at the three
  minute ceiling. These need a device; the widget tests have no camera plugin,
  so the panel is exercised in its waiting and failed states only.
- Playback of a recorded file on Android: the same `NexVideoPlayer` the
  gallery path already uses, but a file produced by this gesture has not been
  played back on this machine.

## 8. Every Android notification, audited

### What was looked at

All five paths that can put something in the shade: note reminders, the
recurring/commitment alarm, scheduled-note arrivals, module alarms (Habits,
Medicine, Parking, …), «Cycle», the daily nudge (posted by
`NexDailyNudgeReceiver` with no Flutter running), the update download
(`DownloadService`, and the Dart fallback through the plugin), the
quick-capture shortcut, and the two settings diagnostics. Both halves were
read: the Dart builders in `lib/platform/reminders*` and the native posters.

### What was wrong

- **A body with no way to read it.** Module and «Cycle» reminders queued real
  text as the body but built the style with `nexNotificationStyle(null)`. In
  the expanded shade that is one truncated line with no more to open — the
  reminders with the most to say were the ones that said least.
- **The same sentence twice.** Nothing stood between a title and a body that
  happened to match. Modules can pass both, and a one-line daily plan can too,
  and Android draws them one under the other.
- **Blank edges.** A body ending in a newline — the natural result of a note's
  last line — was drawn as an empty line between the words and the buttons.
  The native daily receiver trimmed its own copy only from the end, and not
  the start.
- **Two languages for the same two buttons.** A habit reminder's actions were
  written inline as `fa ? 'ثبت پیشرفت' : 'Log progress'` while every other
  reminder read `NexChannelText`, the same table that names the channels. One
  language change would have had to find both.

### What changed

- **One place for the words.** `nexNotificationWords(title, body)` trims both,
  folds doubled blank lines to one, drops blank edges, and returns no body at
  all when the body is empty or only repeats the title. Every scheduler — note,
  commitment, cycle, arrival, module, daily nudge, download, test — now goes
  through it, and the style is always built from the same cleaned body it
  sends. `nexAndroidNotificationText` and `nexNotificationStyle` clean up
  again on their own, so a caller that reaches them directly cannot bypass it.
- **Expanded text everywhere it exists.** Module and cycle reminders now get
  the big-text style their bodies earned. Title-only notifications (a
  recurring item, a download's final card) keep the default style: an empty
  body is not invented for them.
- **Native daily nudge in step.** Its HTML is trimmed at both ends, and when
  the plan's greeting and its chosen line are the same sentence the body is
  not set — the same rule as Dart's, applied where the nudge is posted without
  the app running.
- **The habit buttons moved beside `Done` and `In an hour`** in
  `NexChannelText`, in both languages, so all four action labels come from one
  table.
- **Reviewed and deliberately left alone:** grouping (each reminder belongs to
  its own note or item, and grouping them would hide the one that matters
  behind a summary), the ids and channels (renaming a live channel would reset
  the sound and importance the user chose), the lock-screen policy (app lock →
  `secret`; everything else keeps the framework's own private default), the
  two download ids (`4` native, `3` plugin fallback — they never run for the
  same transfer, and changing either would invalidate a pending cancel), and
  the quick-capture shortcut's `IMPORTANCE_MIN` channel (an ongoing control,
  not an alert).

### Tests

- `test/notification_shape_test.dart` (11, new): the words helper's dedupe,
  trimming, blank-line folding and empty cases; escaped once, not twice; no
  trailing `<br>`; the style carrying the same clean words; a module reminder
  really handed a `BigTextStyleInformation` with its body (the regression);
  a title-equals-body reminder posted with no body; and all four habit action
  labels in English and Persian.
- The notification group was re-run whole — `nex_250_polish`,
  `reminder_body`, `module_reminder_alarm`, `habits_notification_platform`,
  `habits_brief_notifications`, `recurring_notification`,
  `daily_nudge_content`, `daily_nudge_coordinator`, `nudge_name`,
  `download_notice` — **94 tests green**, and the suite's `flutter analyze`
  reports no errors or warnings.
- The native receiver compiles against `android-36` with `javac` (the one
  change there: trimming both ends and the duplicate check).

### Not run here

- A real shade: collapsed and expanded rendering of a long Persian/English
  mix, a lock screen with the app lock on, TalkBack reading the actions, and
  Android's grouping/bundling on a phone with several reminders at once. Those
  need a device; what is checked here is the exact text, style and action
  objects handed to the plugin, plus the native poster's compilation.
