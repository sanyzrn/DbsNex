# Nex add-on sources

All 11 supplied modules are checked into this directory, including their source,
tests and original documentation. All 369 files from the supplied `addon.zip`
are preserved, with only the repository's LF line-ending normalization applied
(archive SHA-256
`28b2cfa90b8f8f86a87524543bbd4aabcce4d4bb89fe67c330188d2878a8b893`).

These are staged sources, outside the app's runtime registry. Review and activate
them one at a time on the shared `codex/2.0-polish` branch. The app currently keeps
its existing module availability. Do not copy all modules into the app in one go.

## Inventory

| Directory | Purpose | Suggested review order |
| --- | --- | --- |
| `habits-module` | Daily/weekly habits and check-ins | 1 |
| `price_lens-module` | Offline unit-price comparisons | 2 |
| `lent_borrowed-module` | Money/item loans and repayments | 3 |
| `expenses-module` | Manual income, expenses and budgets | Later |
| `gold-module` | Manual gold and jewelry calculations | Later |
| `words-module` | Vocabulary and spaced review | Later |
| `parking-module` | Manual parking clues and paid-until tracking | Later |
| `medicine-module` | Medication records, stock and dose logs | Later |
| `warranty-module` | Products, warranty dates and claim records | Later |
| `maintenance-module` | Equipment, service logs and meter readings | Later |
| `smoke_free-module` | Smoke-free progress and craving logs | Later |

## Initial compatibility check

On the 2.0.0 baseline, all 11 modules were copied into an isolated client checkout
and temporarily registered together. Analysis of their sources/tests was clean;
926 module and Module Kit tests passed. No new package or platform dependencies
were required. This checks compatibility with the current API, not device or
release readiness. The normal app CI does not execute tests staged here.

Before each activation, follow [the Module Kit guide](../docs/18-module-kit.md),
move that module's `lib/modules/<id>` and `test/modules/<id>` into `apps/client/`,
add its registry entry, reconcile its planned-module entry, and run the normal
client checks. Use `git mv` so the original source history stays readable.
Review its UX with the current shared glass surfaces, Persian/English, both
directions and both brightness modes before enabling it.

## Scope to verify before activation

- Most modules use local JSON storage and manual input. There are no live price
  feeds, banking integrations, OCR, or dictionary/AI services in these sources.
- Parking does not yet capture GPS, maps or photos. Receipt references in warranty
  are text; they are not file attachments.
- Dates in several modules use an explicitly labeled Gregorian fallback. Review
  Jalali date entry/display before releasing a module to Persian users.
- Module Kit does not expose background reminders or the shared text-field/date
  picker APIs yet. Medication, maintenance, warranty and parking tracking do not
  schedule notifications.
- Storage recovery tests cover the current CRUD API; they do not establish
  cross-process transactions. Review concurrent writes and backup/restore as each
  module is integrated.
- Some original READMEs refer to a `review/VALIDATION.md` that was not included in
  the supplied archive. Use the checked-in tests and current integration checks.
