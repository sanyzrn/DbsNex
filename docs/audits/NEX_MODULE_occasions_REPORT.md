# Birthdays & occasions (`occasions`) — deep audit, upgrade & patch report

**Repository:** `sanyzrn/DbsNex` · **Audited commit:** `9bc92e223395455bb488d52292ef95d8955f0b2b` (`Release/2.9.5 (#523)`, `main`) · **Patch:** `NEX_MODULE_occasions_FIXES.patch`, generated as `git diff 9bc92e2 <work>` against exactly that commit.
**Scope:** `apps/client/lib/modules/occasions/**` (7 files) + `apps/client/test/modules/occasions/**` (3 files, 2 new) + the module `README.md` + the two user-facing changelogs — 12 files in the patch, nothing else in the app touched: no registry, no kit files, no ARB, no other module.

---

## What was audited

Every file of the module (~3,200 lines: model, Jalali/Gregorian math, screen, sheet, detail, greetings, visuals, reminders, glance/dues, draft guard), its README, the module-kit rules (`docs/18-module-kit.md`, the import/forbidden-code gate in `test/module_kit_test.dart`, the shared rules in `test/module_shared_rules_test.dart`), the design language (`docs/16`, `docs/26`), and every consumer of the module's data outside it: the pinned tile (`pinned_module_summary.dart` → `glance`), the quick view (`module_peek.dart`), the home dates card (`tool_dates.dart` → `dues` + `private`), the assistant context (`tools_for_assistant.dart`), the reminder platform and the notification destination (`NexModuleTarget('occasions', …)`). The Jalali arithmetic was checked against the app's own `nexPersianDate`/`nexGregorianDate` (jalaali-js v1.2.8 port, years 1–3177). Baseline before any change: the module's 39 tests, `flutter analyze --fatal-infos`, and the format gate — all green on the repo's own pinned toolchain.

The toolchain is the repo's own pin: **Flutter 3.47.9 / Dart 3.13.7** (`.fvmrc`), installed for this audit; nothing in the patch depends on a different SDK.

## Confirmed bugs and weaknesses (each verified in code, not guessed)

1. **A remembrance's name was put on the home-screen tile.** `occasionsGlance` took `dues.first` — any occasion, including a `memorial` — and made its title the `headline` that `nexPinnedModuleSummary` shows on the home tile, visible without any tap. That contradicts the module's own rule (`occasions_shared.dart`: "A remembrance is private: its name never leaves the module unasked") and the privacy chain every other surface honours: the dates card folds private dues into a count, the assistant text test asserts `isNot(contains('memorial'))`, and the notification for a memorial is deliberately neutral (`notifNeutral`). Only the tile leaked.
2. **White words on the kind colours failed contrast, measurably.** The hero card, the calendar tile's month band and the «today» pill draw white text on the raw kind gradients. Measured with the app's own `nexContrastRatio`: birthday `#FFB347` = **1.78:1**, birthday `#FF7A59` = 2.57:1, other `#3FA9F5` = 2.56:1, anniversary `#E2557B` = 3.61:1 — below the 3:1 large-text floor and far below the 4.5:1 normal-text floor everywhere a date line or month name sits.
3. **Reminder lead times offered {0, 1, 3, 7} while the kit's one set is {0, 1, 3, 7, 14, 30}** and the model accepts 0–30. A record kept with `remindDays: 14` or `30` (imported, synced, or set by an earlier version) opened in the editor with **no chip selected** while still ringing — the UI silently disagreed with the data.
4. **Editing a broken record dropped the typed day.** The sheet seeded the day field only when `o.valid` — a record with an impossible month (13) but a real day lost its day on edit, so the person retyped what they had already typed. (`day` itself was in 1–31.)
5. **List rows were unusable at size and unreadable as units.** With a household's worth of dates there was no way to find one person without scrolling every section; and a row exposed its five visual pieces (name, kind, age, pill, tile) to the screen reader as separate stops, with the countdown ring's number not announced as anything (no label, no unit).
6. **Adding the same person twice was silent.** The same name on the same day of the same calendar — the classic double-entry of a birthday — saved without a question; the pair then reads as two birthdays a day apart in every list.

Deliberately **not** treated as bugs (checked, house-intended): `draft.changed()` in `build` writes a checkpoint for an untouched form — this is the pattern every module uses (`warranty/editor_checkpoint.dart:136`, `medicine`, `smoke_free`), the phantom draft is invisible and cleared on cancel, and changing it here alone would diverge from the house style; the month dropdown's `initialValue` sync is handled by `_DropdownButtonFormFieldState.didUpdateWidget` in the pinned SDK (verified in the SDK source); `occasionAlarmPlan`'s past-alarm skipping, DST-safe `daysUntil`, the two-occasion renewal window and the `withdrawReminder` vs `clearReminder` distinction are all covered by the existing tests and left alone.

## Implemented fixes and UX/UI improvements

| # | Change | Where |
|---|---|---|
| 1 | **The tile never names a remembrance.** The glance now leads with the next date that *may* be named; when every date is a remembrance, one neutral line — «A date you keep is coming up», the notification's own words — plus *when* it is. Facts (the tap-opened quick view) keep naming dates, exactly as the medicine module keeps names for the tap-opened view. | `occasions_shared.dart`, strings `glancePrivate` (en/fa) |
| 2 | **Readable kind colours.** One shared constant `occasionColourScrim = 0.42` and `occasionDeepen()` deepen every gradient white words sit on — hero card, tile month band, «today» pill — and the ink of the «this week» pill and the favourite star. Measured, all ends of all gradients now carry white at **4.93:1 or better** (birthday 6.56/4.93, anniversary 8.39/10.19, memorial 11.37/15.22, other 9.26/6.53), pinned by the new `occasion_contrast_test.dart`, which also documents that the raw colours fail (1.78:1) so a future palette change cannot quietly regress. Hero text is now pure white (eyebrow/date/ring label lost their 0.85–0.92 alphas). | `occasion_visuals.dart` |
| 3 | **Every row and the hero read as one line to a screen reader**: "Sara, Birthday, in 4 days, turns 30" (`Semantics(button:, label:, excludeSemantics:)`, the expenses pattern). The countdown ring announces «in N days» / «today» instead of a bare number. On the day itself the card's copy/share buttons stay reachable — the hero excludes its children's semantics only when it carries no actions (a regression caught in self-review and fixed). | `occasion_row.dart`, `occasion_visuals.dart` |
| 4 | **Search in the list**, the house `NexSearchField` from the bar (toggle icon, clear button, direction follows the typed script): matches the name **and the note** (where the gift ideas live), folded with the app's `nexSearchFold` — the Arabic yeh finds the Persian one, a ZWNJ cannot hide a word, digits match in both scripts. Flat results, nearest first; a «No dates match …» empty state; offered only once there is something to search. | `occasions_screen.dart` |
| 5 | **The duplicate guard.** Saving a name that already keeps the same day of the same calendar asks once — «Already kept? — {name} keeps this same day.» — with *Save anyway* / cancel; names compared folded. Adding a birthday twice is now a decision, not a silent extra. | `occasion_sheet.dart` (`duplicateOccasionName`), dialog keys `occasion-duplicate-stay/save` |
| 6 | **The full lead-time set**: 14 and 30 days before join the chips; a record kept at one of them shows its choice. | `occasion_sheet.dart`, strings `remindTwoBefore`/`remindMonthBefore` |
| 7 | **A broken record keeps its typed day** when opened for editing — fixing the month no longer erases the day. | `occasion_sheet.dart` |

## New features and creative enhancements

- **Search (4)** and the **duplicate guard (5)** above are the two workflow-level additions; everything else sharpens what exists.
- The glance's neutral line reuses the notification's own sentence, so a memorial reads identically wherever it is not named — one privacy voice instead of two.

## Architectural and performance notes

- No new imports beyond the module kit's API (`NexSearchField`, `nexSearchFold`, `NexAlertDialog` all arrive through `module_api.dart` — the kit gate re-run confirms the module still passes every import rule).
- No record shape changed: v1 records are read exactly as before (`remindDays` 0–30 was already the model's contract); unknown fields are still preserved on every write path (`_patch`, `_save`, delete-undo).
- Search runs on the already-loaded list in `build`, one fold per occasion — the fold is a precompiled-regex pass (`nexSearchFold`), no allocations per keystroke beyond the folded strings; the results list reuses the existing `OccasionRow` builder.
- `occasionDeepen` is a constant alpha blend computed per `gradient` getter as before (same cost as the old `LinearGradient`), and the contrast test is pure arithmetic — no pump, no golden.

## Research findings relevant to Iranian users

Checked against what Persian birthday/reminder apps on the Iranian markets actually offer (Cafe Bazaar's «کامل ترین برنامه یادآور تولد فارسی با تقویم شمسی و میلادی», Myket's سن‌یار, Yadavar): Jalali-first entry, both calendars, age display, reminders on the day **and** several days before, and ready-to-send greetings are the expected baseline — this module already covers all of them, and deliberately does **not** do the one thing those apps do that Nex's philosophy forbids (sending SMS on the person's behalf / reading contacts). The module-kit audit confirms contacts/calendar import, a true yearly reminder, CSV/ICS export and a home-screen widget remain **platform requests** — impossible from inside the module folder, correctly deferred to the kit's growth path. The genuinely valuable additions within those limits were judged to be: finding a person in a family-sized list (search), not paying attention twice (duplicate guard), reading the card in daylight (contrast), and screen-reader correctness for Persian (RTL semantics, folded search).

## Tests performed and actual results (all actually run, on Flutter 3.47.9 / Dart 3.13.7)

| Check | Result |
|---|---|
| Baseline before any change: module's 39 tests | **39/39 passed** |
| Module suite after the patch: **56 tests** (39 kept + **17 new**: 5 glance-privacy, 6 contrast, 6 search/duplicate/lead-times/semantics) | **All passed** |
| `flutter analyze --fatal-infos` (whole app), before and after | **No issues found** |
| Full client suite, run in chunks on the patched tree (root tests incl. timeline/home/UI-consistency/visual-audit guards, module kit gate, then every other module, goldens, performance) | **All chunks passed** (one flutter_tools listener-cleanup flake at finalization was observed on a full single run — a tooling artifact, not a test failure; every chunk re-run to an explicit verdict) |
| `tools/check_changed_format.py` (the repo's own format gate) on the patched tree | **exit 0, 0 files to fix** |
| Module-kit gate, glance, pinned summaries, assistant privacy, shared rules, peek, due labels, notification destination | **All passed** |
| Visual verification: the screen rendered in EN and FA at 430×932 and captured; pixels analysed — hero region dominated by the deepened terracotta `#944d32`/`#946829` family with white text present in both locales; no blank or broken render | **Verified** |
| **Patch integrity on a pristine clone**: `git clone` → `git checkout 9bc92e2` → `git apply --check` → apply → `flutter pub get` → occasions suite + analyze + cross-cutting gates (136 tests) | **`git apply --check` OK; 56/56 passed; analyze clean; 136 gates passed** |

## Patch application instructions

```bash
git clone https://github.com/sanyzrn/DbsNex.git
cd DbsNex
git checkout 9bc92e223395455bb488d52292ef95d8955f0b2b   # the audited main commit
git apply --check NEX_MODULE_occasions_FIXES.patch      # should print nothing
git apply NEX_MODULE_occasions_FIXES.patch
cd apps/client && flutter pub get                        # Flutter 3.47.9 (.fvmrc)
flutter test test/modules/occasions/                     # 56 tests
flutter analyze --fatal-infos                            # clean
```

`git am` is not required — this is a plain unified diff; `git apply` is enough. The patch contains no binary or generated files.

## Remaining limitations, risks and unverified areas

- **Unverified on a real device/emulator:** no Android/iOS build was run in this sandbox (tests ran on the Flutter test runner with the repo's pinned SDK). The visual check was a rendered capture plus pixel analysis, not a human eye on a phone.
- **Search scope:** active occasions only (archived ones are not searched — consistent with the list, which keeps them behind a toggle), and by name/note, not by date. Deliberate; a date-range filter would be the next step if lists grow past a household.
- **The duplicate guard is a question, not a block** — a person can keep two «Sara»s on the same day on purpose. It compares name + calendar + month + day, folded; near-duplicates («Sara's birthday» vs «Sara») are intentionally not second-guessed.
- **The house-wide untouched-form draft checkpoint** (writes a draft for a form opened and left alone) is pre-existing module-kit behaviour shared by every module; changing it belongs to the kit, not to this module's patch.
- **Contrast:** the deepened colours clear 4.5:1 at every gradient end (the test pins the mechanism, not a single value); the kind colours are still fixed constants — a future palette change is exactly what the new test guards against.
- **Out of scope by design:** contacts import, a true yearly alarm, CSV/ICS export, home-screen widgets — all listed in the README's Platform requests; they need kit APIs the module cannot reach.
- The two changelog entries (EN/FA) are one bullet each under «Unreleased», matching the repo's convention; if maintainers fold them into a different release header, the patch still applies (the hunk is positional).

## Integration follow-up

Applied the source patch against its exact audited base. Additional static-review fixes: retain the search field with zero matches and reject empty folded queries; lock the save flow before duplicate lookup and handle lookup errors in the existing save error path; expose explicit semantic tap actions on rows and hero cards; extend the search widget regression test to recover from zero matches. The test results above are those reported by the original auditor, not a new execution. Flutter is not available in the integration environment; rerun CI before merging.
