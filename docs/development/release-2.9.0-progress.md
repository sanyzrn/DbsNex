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
| 2 | One engine for Smart Summary and Daily Nudge | not started |
| 3 | Intelligent greeting: local first, AI second | not started |
| 4 | Keyboard / focus / input audit | not started |
| 5 | Quick Capture: seamless code mode | not started |
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
