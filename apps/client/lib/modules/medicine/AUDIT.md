# Medicine module — deep audit & upgrade report

**Repository:** `sanyzrn/DbsNex` · **Branch:** `agent/module-medicine-audit` (from `main` @ `a36b5f4`, v2.9.3)
**Scope:** `apps/client/lib/modules/medicine/**` + its tests + module README + user-facing changelogs. Nothing else in the app was touched; `module_rollout.dart`, registry, ARB, pubspec, other modules — untouched.

---

## What I audited

Every file of the module (~6,800 lines: cabinet, Today, Expiry, detail sheet, editor, boxes, places, reminders, schedule, money, drafts/journal, strings), its README and briefs, the module-kit rules (`docs/18`), the design language (`docs/16`), the shared `duesBetween`/`summarize`/glance surfaces, and the module's 106 inherited tests (all re-run, all green). Iranian-market fit was reviewed against what the module already promises: Jalali dates, tomans, person-as-`{"name": …}`, Saturday-first weeks, Persian digits, privacy-first behavior, no medical advice.

## Bugs fixed (each with a regression test)

| # | Bug | Fix |
|---|---|---|
| 1 | **The cabinet's Today card counted answered doses as open.** It said "N doses today" all day no matter what was logged — the screen never read the dose logs (README promised "how many moments are still open"). | The screen loads doses; the card counts **open** moments and says **"All of today's doses are logged"** when none are left. |
| 2 | **A dose logged from the detail sheet never answered its routine moment** — anywhere. `duesBetween` matched only slot-carrying logs, so the quick view read "0 of 3 doses today" and the home screen's dates stayed un-done for a person who logs from the medicine's own page. | One shared match (`MedicineShared.answeredKeys/answers`): a log answers its `slot` **or** its own clock time — exactly what the Today page always did. Card, quick view, home dates and Today now read the same truth. A log whose action is neither taken nor skipped answers nothing. |
| 3 | **Persian readers saw English.** `noMedicinesFor` in the FA map was the untranslated English sentence. | Proper Persian: «برای این شخص هنوز دارویی ثبت نشده است.» Plus a guard test: every FA line must contain Persian script. |
| 4 | **The duplicate-name dialog asked "Delete {name}?"** — it reused the delete dialog's body for a question that isn't about deleting. | New `duplicateBody` in both languages: "Keep both, or go back and change the name — nothing is saved yet." |
| 5 | **"Me" was missing from the person filter** — the README promised it ("me included"); a mixed household could not see only their own medicines. | A "Me" chip beside the names, shown when the list mixes "me" with named people; mutually exclusive with the name chips. |
| 6 | **Both day rules looked alive.** Weekdays silently win over "every N days" (a documented rule), but the editor and detail sheet never said so. | A quiet note under the fields, in both places, when both are written. |

## Experience upgrades (Iranian household first)

- **The next dose is the first thing you read.** Each cabinet row carries "Next at 21:00" for the next open moment still ahead (primary colour), or a quiet teal "All of today's doses are logged" when the day is done. Nothing is invented when every open moment has passed.
- **A "Next" heading on the Today page** — the first open moment at-or-after now carries the panel's own heading, so a long list needs no scanning.
- **Per-slot busy.** Logging one moment no longer locks every button on the page; two taps in one breath both land (test-pinned).
- **Today rereads the day on app resume.** A page left open overnight stops calling yesterday "today".
- **Long histories open fast.** The detail sheet builds the newest 14 rows and offers "Show all (N)" — a 3×-daily routine kept for months used to build 1,000+ rows on open (real jank on the budget Androids common in Iran).
- **Summary cards are tappable everywhere**, not only on the small button.
- Persian side-by-side verified (Vazirmatn dark capture re-rendered and checked); Saturday-first weekday order, Persian digits and toman grouping unchanged and still covered by the inherited tests.

## Deliberately not done (and why)

- **Boxes counting into stock** — README open question; informational boxes keep the one quantity a taken dose moves honest.
- **Raising the reminder caps** (32/medicine, 160/cabinet) — platform alarm limits; the OS-owned repeating reminder remains the requested fix.
- **Search in the cabinet** — module records are excluded from app search by design; typical lists are household-sized.
- **No new record fields, no migrations** — every change reads existing v1–v3 records as they are; unknown keys still preserved.

## Tests & validation (Flutter 3.47.9 / Dart 3.13.7 — the repo's own pin)

| Check | Result |
|---|---|
| `dart format` (module lib+test) | clean |
| `flutter analyze --fatal-infos` (module, tests, **whole client**) | no issues |
| Module suite | **134 passed** (was 106; +12 today-progress logic, +13 audit surfaces incl. concurrent logging, +2 shared-shape) — every inherited test untouched |
| Module kit gate · whats-new · file-size | all green |
| All 20 module suites | 2,060 passed |
| Full client suite (chunked) | ~4,850 passed, 0 failed |
| Visual | cabinet re-rendered in EN-light/FA-dark at 1× and 2× text (`screen_review_test`), layout verified, no overflow |

## Remaining limitations

- The two refreshed cabinet captures (`review/*.png`) could not travel through the text-only GitHub API; regenerate with
  `flutter test test/modules/medicine/screen_review_test.dart --dart-define=NEX_CAPTURE=<dir>` (done and verified locally during the audit).
- Reminders still stop when a non-daily routine's phone stays closed past the 8-day horizon — needs the platform's OS-owned repeating reminders (already a documented platform request).
- `review/` detail and Today images remain one polish behind (README says so).
- Reminder truncation above 160 alarms stays silent (platform cap); newest medicines win.
- Device checks (TalkBack/VoiceOver, real Doze behaviour, release builds) remain maintainer acceptance, as the module's checklist states.

## Maintainer follow-up before merge

- Explicit dose slots take precedence over the clock timestamp, so one log cannot complete two routine moments.
- Midnight (00:00) is included in both Today and cabinet progress.
- Household filters reset when their selection is no longer available; fixed-clock widget tests cover time-dependent cases.
- Added regression tests for midnight and explicit-slot matching. The original audit's test results predate these changes; fresh CI is required.
