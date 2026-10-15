# Nex add-on sources

All 11 supplied modules are integrated into the client for individual review. Sources and original READMEs are under `apps/client/lib/modules/<id>/`;
tests are under `apps/client/test/modules/<id>/`. They were moved from this
folder with Git history preserved. All 369 supplied files are retained, with the
repository's LF normalization (original archive SHA-256
`28b2cfa90b8f8f86a87524543bbd4aabcce4d4bb89fe67c330188d2878a8b893`).

All modules default off from 2.0.2, including upgrades from the automatic
2.0.1 preview. Explicit Add/Remove choices are preserved; Cycle keeps its existing
opt-in. Add the modules you want from Tools → Add modules. Continue all work on
`codex/2.0-polish` and complete each module individually.

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
- Dates in several modules use an explicitly labeled Gregorian fallback. Review
  Jalali date entry/display before releasing a module to Persian users.
- Module Kit does not expose background reminders or the shared date picker yet.
  The shared `NexTextField` is now exported and used by the multiline notes in
  Habits, Lent & Borrowed and Smoke Free; other local editor fallbacks can be
  reviewed individually. Medication, maintenance, warranty and parking tracking
  do not schedule notifications.
- Storage recovery tests cover the current CRUD API; they do not establish
  cross-process transactions. Review concurrent writes and backup/restore as each
  module is integrated.
- Some original READMEs refer to a `review/VALIDATION.md` that was not included in
  the supplied archive. Use the checked-in tests and current integration checks.
