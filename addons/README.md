# Nex add-on sources

> All thirteen modules are available: Cycle, Habits, Price Lens, Lent & Borrowed, Quit Habits and Birthdays & occasions (built later, on the kit) from 2.1.11–2.1.13, and Expenses, Gold, Words, Parking, Medicine, Warranty and Maintenance from 2.1.14. Source, installation choices and records are preserved; the limits listed below still hold.

All 11 supplied modules are integrated into the client for individual review. Sources and original READMEs are under `apps/client/lib/modules/<id>/`;
tests are under `apps/client/test/modules/<id>/`. They were moved from this
folder with Git history preserved. All 369 supplied files are retained, with the
repository's LF normalization (original archive SHA-256
`28b2cfa90b8f8f86a87524543bbd4aabcce4d4bb89fe67c330188d2878a8b893`).

All modules default off from 2.0.2, including upgrades from the automatic
2.0.1 preview. Explicit Add/Remove choices are preserved; Cycle keeps its existing
opt-in. Add the modules you want from Tools → Add modules. Continue all work on
`codex/2.0-polish` and complete each module individually.

## Module upgrade after 2.1.10

A separate upgrade pass over all eleven modules was reviewed and merged on top
of the 2.1.10 code, with the rollout left as it was; 2.1.11 then finished and enabled Habits, Price Lens and Lent & Borrowed (see below).
It brings the shared Jalali date entry/display (`NexModuleDateEntry`,
`nexModuleDateLabel`) to every module, the shared `NexTextField` to every
multiline field, optional system reminders (`NexModuleReminderControl`) to
Parking, Warranty, Maintenance and Medicine, about forty fixes (stable sorts,
singular/plural strings, wrong "expired" state, Gregorian-only medicine dates,
lent/borrowed draft migration) and 134 more tests. Saved records and drafts
stay readable: dates keep their ISO form on disk and old Lent & Borrowed drafts
are migrated on open. Re-enable each remaining module individually after a
device check (TalkBack, notification permission, large text) — add its id to
`nexAvailableModuleIds` in `apps/client/lib/modules/module_rollout.dart`.

### Finished and enabled in 2.1.11: Habits, Price Lens, Lent & Borrowed

Looked at in screenshots (Persian dark, English light, sheets and detail
pages) against the app's own pages, then changed: the shared date entry puts the
calendar button beside the field instead of under it; a page with no records
shows one button, not that button and the floating one; reminder messages use
the top capsule (`nexShowBanner`, now in the module API) instead of a
SnackBar. Added: Habits' optional daily reminder (a repeating module
reminder, `NexModuleStore.setDailyReminder`, restored on launch); Lent &
Borrowed's optional due-date reminder, withdrawn when the loan is settled or
deleted; Price Lens' Copy result (`nexModuleCopyText`). Tests:
`test/modules/reviewed_three_test.dart`; rollout tests now expect the four
available ids. Not done, still open: real-device check of notifications,
TalkBack, and Price Lens barcode/OCR (outside the module API).

### 2.1.12: from the three benchmark reports

- **Lent & Borrowed:** per-currency totals (never summed across currencies),
  search and filters, a page per person (grouped by the name folded for case,
  spacing and Arabic yeh/kaf — no stable person id yet, so two people with one
  name are one person), polite reminder messages shared only from a tap.
  Receipts and photos, contact picking, CSV/PDF export, instalments: not done —
  they need file, contacts or export APIs the module kit does not expose.
- **Price Lens:** a one-sentence result with the percentage (display only, the
  ranking stays exact), per 100 g / 100 ml units. Barcode/OCR, length/area
  units, price charts: not done.
- **Quit Habits (`smoke_free`):** not merged into Habits — building a streak
  and counting time since quitting are different records and different screens
  — but named beside it. Generalised from cigarettes to presets and custom
  habits, several at once; records from before (kind `quit`, `craving`) read as
  cigarettes and are written back unchanged. Added: live counter, future start,
  money and time kept, saving goal, a reason, marks, five-week grid, the help
  sheet (4-7-8 breathing, ten-minute wait, tips), a one-time safety note for
  alcohol. Not done: reminders, daily confirmation, charts beyond the grid.

### 2.1.13: the thirteen benchmark reports, checked against the code

A report was used only where the code showed it was right and the module kit
allows it; several claims were already true in the code (shared Jalali date
entry, reminders, per-currency totals) and some asked for platform interfaces
the kit does not have.

- **Done, in an available module:** Habits — a month calendar in the reader's
  own calendar where any day up to today can be marked or taken back, and a
  completion rate over the days since the habit began (never a miss before it
  existed). New module **Birthdays & occasions** (`occasions`): Jalali and
  Gregorian dates that repeat in their own calendar, 29 February / 30 Esfand
  policy, unknown year, countdown, greeting, an optional reminder (two kept
  ahead, renewed on opening — a module has no yearly alarm).
- **Done, in a module still Soon (so not yet visible):** Gold Check — budget →
  heaviest weight that fits (exact, monotone search), the making charge as a
  share of the metal, copy the estimate. Words — meaning-first review, copy
  the list in the paste box's own format. Expenses — this month against last,
  per currency. Warranty — copy/share the service file; says when no invoice
  or serial is written. Maintenance — copy/share the service history. Parking
  — share where the car is.
- **Shared:** `nexReadableDate`, `nexDigits`, `nexPersianDate`,
  `nexGregorianDate`, `nexPersianMonthDays` in the module API;
  `NexModuleMonth` and `nexModuleMonthName` in `module_dates.dart`.
- **Left out on purpose:** Cycle (almost complete: confidence, cycles counted,
  report and calendar are there; trend charts and symptom filters need their
  own design). Medicine "Today" view and reminders (its days are free text,
  so a schedule would be guessed — health, so not guessed; needs device
  testing). Habits weekday / every-N-days schedules (they change the streak
  rules). Expenses Jalali months (budgets are keyed by Gregorian month — a
  migration, not a tweak). Photos, OCR, barcode, contacts, CSV/PDF export,
  GPS, maps, TTS, FSRS, and live prices — outside the module API.
- **2.1.14 — the last seven enabled.** Expenses, Gold, Words, Parking,
  Medicine, Warranty and Maintenance went through the same review as the
  first six (calendar button, one primary action, Persian layout, large text,
  dark) and are available. Shared: a typed date shows the same day in the
  reader's own calendar under the field (`NexModuleDateEntry`); Expenses shows
  the Jalali span of the month; empty pages carry one button, the floating
  one appears once there is something on the page. Sheets lift above the
  keyboard centrally in `nexShowSheet`. Not verified on a device: reminders,
  TalkBack, real keyboards — test on the phone.

## Inventory

| Module ID | Purpose | Suggested review order |
| --- | --- | --- |
| `habits` | Daily/weekly habits and check-ins | 1 |
| `price_lens` | Offline unit-price comparisons | 2 |
| `lent_borrowed` | Money/item loans and repayments | 3 |
| `expenses` | Manual income, expenses and budgets | Later |
| `gold` | Manual gold and jewelry calculations | Later |
| `words` | Vocabulary and spaced review | Later |
| `parking` | Manual parking clues and paid-until tracking | Later |
| `medicine` | Medication records, stock and dose logs | Later |
| `warranty` | Products, warranty dates and claim records | Later |
| `maintenance` | Equipment, service logs and meter readings | Later |
| `smoke_free` | Smoke-free progress and craving logs | Later |

## Initial compatibility check

On the 2.0.0 baseline, all 11 modules were copied into an isolated client checkout
and temporarily registered together. Analysis of their sources/tests was clean;
926 module and Module Kit tests passed. No new package or platform dependencies
were required. This checks compatibility with the current API, not device or
release readiness. The integrated tests now run in the normal client CI.

The runtime registry includes all eleven modules, and the corresponding planned
cards were removed to avoid duplicates. The Module Kit gate validates the imports,
record boundaries, registration and bilingual strings. Follow
[the Module Kit guide](../docs/18-module-kit.md) for later changes and verify UX in
Persian/English, both brightness modes and with large text as each module is
completed.

## Remaining scope for individual review

- Most modules use local JSON storage and manual input. There are no live price
  feeds, banking integrations, OCR, or dictionary/AI services in these sources.
- Parking does not yet capture GPS, maps or photos. Receipt references in warranty
  are text; they are not file attachments.
- Jalali date entry/display is done in every module (see above);
  verify it on a device before releasing a module to Persian users.
- Module Kit exposes the shared date entry and an optional reminder control as
  of 2.1.3 and the modules use them (see above).
  Every multiline field uses the shared `NexTextField`. Medicine, Maintenance,
  Warranty and Parking can schedule an optional reminder; the others do not.
- Storage recovery tests cover the current CRUD API; they do not establish
  cross-process transactions. Review concurrent writes and backup/restore as each
  module is integrated.
- Some original READMEs refer to a `review/VALIDATION.md` that was not included in
  the supplied archive. Use the checked-in tests and current integration checks.
