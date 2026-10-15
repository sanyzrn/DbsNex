# Lent & borrowed

## 1. What it does

Lent and Borrowed have separate tabs, outstanding and settled sections, and
due/overdue wording. The current tab supplies the default direction for New.
Record money in a chosen currency or an item with integer quantity, person,
issue date, optional due date and note. Partial/full returns have their own
dated history; deleting an accidental settlement corrects it, with Undo.
Edit details/total without clearing returns. Currency/type are locked while
any returns exist, preventing reinterpretation of their units. Delete restores
the full record/history with Undo. Empty/loading/error/large-text states work.
There are no background reminders, currency conversion, contact/camera/banking
integrations, collection advice, network access or independent cloud sync.

## 2. Records

Kind `loan`, stable store-generated ID, schema v2:

```json
{"v":2,"direction":"lent","person":"Sara","type":"money","amount":12500,"currency":"USD","currencyDecimals":2,"what":"","issued":"2026-10-01","due":"2026-10-15","note":"tickets"}
```

`direction`: lent/borrowed; `person`: string; `type`: money/item;
`amount`: integer money minor units OR item count; `currency`: three-letter
code; `currencyDecimals`: integer 0–4; `what`: item description string;
`issued`: local civil date key; `due`: date key or null; `note`: string.
Legacy loans without currency remain IRR whole rials; amounts are never scaled
on read. Missing/invalid fields default to lent, money, empty text, zero amount,
today issue date and no due date. Impossible dates are rejected, not normalized
to a different deadline. Edits merge the existing body, retaining unknown fields.

Money is an **integer count of the selected currency's minor units**. The
offline table contains 165 current currency/fund codes with known precision,
verified from [SIX's ISO 4217 List One](https://www.six-group.com/dam/download/financial-information/data-center/iso-currrency/lists/list-one.xml)
on 2026-10-12. Examples: USD/EUR 2 digits, JPY/KRW 0, KWD/BHD 3, CLF 4.
**IRR deliberately uses whole rials (0 digits)** to preserve the original Nex
contract and existing records; this differs from ISO's listed minor-unit scale.
There is no currency conversion, exchange-rate lookup or total across currencies.

New amounts/prices are limited to `2^53 − 1` minor units, exact on native and web
runtimes. Input uses integer/BigInt parsing, accepts Latin, Persian and Arabic
digits, grouped thousands, and `.` / `٫` decimals. Excess precision, negative
money, malformed grouping, decimal comma and larger values are rejected rather
than silently rounded/clamped. Stored fractional/NaN/infinite amounts default
to zero. Stored currency precision is preserved, including an unknown valid
three-letter historical code; new selections come from the bundled table.

Kind `return`, stable store-generated ID:

```json
{"loan":"l1","date":"2026-10-05","amount":2500}
```

`loan`: parent ID; `date`: local civil key (unknown = empty string);
`amount`: integer minor units or item quantity, in the parent record's units.
Defaults are empty parent/date and zero amount. Dates are displayed truthfully
as relative past/future/unknown values. Returns are not exchanged between
currencies. Full settlement is one return for the exact outstanding remainder,
not a separate boolean. Individual return Undo restores its raw body.

Drafts are stored under kind `draft`, IDs `<editor>:<record-id>` or
`<editor>:new`, with `{v: 1, base: <JSON string of original body>, fields: {...}}`.
Field values are strings from the editors plus typed choices described below.
`fields.recordId` is an optional stable target ID for new records: if that record
already exists, a leftover checkpoint is not reopened as a new unsaved record.
A cleanup failure may replace the draft with `{v: 1, discarded: true}`; this
marker has no fields/base and is ignored on read.
`fields.recordId` is an optional stable target ID for new records: if that record
already exists, a leftover checkpoint is not reopened as a new unsaved record.
A cleanup failure may replace the draft with `{v: 1, discarded: true}`; this
marker has no fields/base and is ignored on read.
`fields.recordId` is an optional stable target ID for new records: if that record
already exists, a leftover checkpoint is not reopened as a new unsaved record.
A cleanup failure may replace the draft with `{v: 1, discarded: true}`; this
marker has no fields/base and is ignored on read.
Serial, coalesced writes keep the latest snapshot; back/swipe keeps it, explicit
Cancel discards it, successful Save clears it. A baseline fingerprint rejects
stale drafts after a final record changes. These records stay in this module's
store/backups and never count toward progress or balances.

Loan draft fields: `person`, `amount`, `what`, `quantity`, `daysAgo`, `dueIn`,
`note` strings; `currency`, `direction`, `kind` keys; `digits` integer;
`anchor` ISO timestamp. Drafts do not create financial liabilities.

Compound deletion uses kind `operation`, ID `<parent-kind>:<parent-id>`, body
`{v: 1, records: [{kind: string, id: string, body: JSON object}, ...]}`.
A complete raw snapshot (children, related edit draft, then parent) is written
before deletion. After success the journal is removed. A failed/interrupted
deletion is restored on the next read. Undo restores raw bodies including
unknown historical fields. The store supplies new `updatedAt` values; original
record IDs and all body data are retained. Atomic transactions are not exposed
by the kit: the recovery journal is the bounded offline fallback.

## 3. Decisions

- Outstanding = total − sum of returns, never negative. BigInt accumulation
  prevents wraparound; corrupted over-returned histories settle at zero.
  Input rejects zero/negative/overpayment, excess precision and invalid dates.
- Return/settlement saves re-read the loan and its returns before validation;
  edits re-check current returns before saving. Totals below returned values
  and unit changes with history are refused. Currency amounts are never mixed.
- **Due offsets are from editor-open today**, consistently on read and save.
  An overdue date is a negative offset. Zero is today; blank is no due date.
  Presets today/7/14/30/none are explicit. Due before issue is refused.
- Unchanged issued/due values are kept exactly, even across midnight. Civil
  shifts use calendar construction through UTC midnights, not 24-hour durations.
  Reopened drafts retain their original anchor. Correcting a name never moves
  the deadline. Gregorian keys remain storage-only; Persian UI uses relative
  wording rather than pretending to show a Jalali picker.
- Due soon = within three days. Overdue first, then today, soon, later, undated;
  settled records are separate. Highlighting is computed on opening/resume/
  interaction, not by a background reminder service.
- Integer units/precision and explicit currency codes are visible in totals,
  remaining values and history, with localized digits and RTL isolation.
- Undo is reversible; compound deletion is checkpointed for recovery. The kit
  offers no transaction across independent store calls, so simultaneous writes
  from separate external editors are not an atomic multi-writer guarantee.

## 4. Guide

**English:** Choose Lent or Borrowed and record money in its currency, or an
item with a count. Set an optional due date relative to today; a negative offset
means the date has passed. Record each partial return and the remaining balance
updates. Mark fully returned for the remainder; delete that return to correct a
mistake. Editing preserves the deadline and history, and deletion has Undo.
Currency/type stay fixed while returns exist. Everything stays local and offline.

**فارسی:** جهت قرض‌داده یا قرض‌گرفته را انتخاب کنید و پول را با ارز خودش،
یا وسیله را با تعداد، ثبت کنید. موعد اختیاری نسبت به امروز است؛ عدد منفی
یعنی موعد گذشته. هر برگشت جزئی را ثبت کنید تا باقی‌مانده به‌روز شود. برای
تسویهٔ کامل، باقی‌مانده را ثبت کنید؛ با حذف همان برگشت می‌توانید اشتباه را
اصلاح کنید. ویرایش، موعد و تاریخچه را نگه می‌دارد و حذف بازگردانی دارد.
تا وقتی برگشت ثبت شده، ارز و نوع ثابت می‌مانند. همه‌چیز محلی و آفلاین است.

## 5. Changelog

- EN: Lent & borrowed: international currencies with exact partial returns,
  stable overdue edits, civil-date deadlines, guarded units and recoverable drafts.
- FA: قرض و طلب: ارزهای بین‌المللی با برگشت جزئی دقیق، حفظ موعد در ویرایش،
  محاسبهٔ تقویمی تاریخ‌ها، حفاظت از واحدها و پیش‌نویس قابل‌بازیابی.

## 6. Platform requests

1. Shared Jalali calendar picker/formatter through `module_api.dart`.
   Relative issue/due offsets and practical presets are the honest offline
   fallback, including overdue dates.
2. Export `NexTextField` for Nex's native per-paragraph note editor. Current
   permitted Flutter input follows content direction; stored notes use the
   exported direction helper. See full-app scanner discrepancy in the report.
3. Optional atomic storage batch / compare-and-write for multi-record balances.
   Re-reading, guarded operations and the deletion recovery journal currently
   work wholly within the module API without a private core dependency.

## 7. Checks

Reviewed in the owner's Windows / PowerShell workspace against Nex `main`
`fdd70f4890b0bab67d30b88d4821273113d4b01d`, with the repository's pinned Flutter **3.35.5** / Dart **3.9.2**.
The installed system Flutter is 3.44.8; a local validation SDK was used instead.

All three modules were temporarily registered in a separate reference checkout
under `.validation/DbsNex`; the original registry is restored after checks.
No core source, ARB, dependencies, registry or planned-catalog edits are delivered.
No Commit, Push, PR, remote write or ZIP was made. `core.longpaths` was supplied
to clone per command rather than changing the owner's global Git configuration.

Commands run from `apps/client` (with the pinned local SDK):

```text
flutter pub get --enforce-lockfile
flutter test --no-pub test/module_kit_test.dart test/modules/habits test/modules/smoke_free test/modules/lent_borrowed --reporter expanded
flutter analyze --no-pub --fatal-infos
flutter test --no-pub --reporter expanded
dart format <module's lib and test folders>
```

`--no-pub` follows successful dependency resolution: Flutter's final Windows
plugin-symlink setup reports missing Developer Mode privileges. Package versions
remain exactly those in the baseline lockfile; only the hosted download endpoint
was changed temporarily to the public Flutter mirror because pub.dev returned
403. Tests run outside the filesystem sandbox after its compiler-temp-file copy
failed with Access denied. Neither workaround changes module code or dependencies.

Final results: **248/248 passed** for the combined module tests and the real
module-kit gate with temporary registration; **full client analyzer clean**.
The full client run reported **1368 passed, 4 failed, 3 skipped**: two Windows
attachment-fixture file-lock cleanup failures, the intentional old planned
Habits entry pending maintainer integration, and the multiline editor/API
discrepancy described above. The Windows failures reproduced with the original
registry. Core: 231 passed/analyzer clean. Data: 253 passed, 2 failed (Windows
symlink privileges), 14 skipped/analyzer clean. Final detailed evidence is in
`review/VALIDATION.md` at the workspace root. Earlier test failures were repaired;
the final log, not the initial README's historical claims, is authoritative.

Tests include Persian RTL and English LTR, light/dark, text scale 2.0 at 320×640,
reduced motion, reopening, isolation, failed writes/retry, draft coalescing,
back waits for the latest durable checkpoint, retry after a failed flush,
and meaningful user journeys. Actual Flutter main-screen captures use Nex's
themes and bundled fonts in Persian dark and English light, under
`review/screenshots`. These are widget renders with test fixtures, not Android-device screenshots.

Maintainer integration: register the three const modules and imports in
`nexModules`; remove the old planned IDs **`habits`, `smoke-free`, `lent`**
(different from the actual IDs `habits`, `smoke_free`, `lent_borrowed`).
Copy the Guide/Changelog paragraphs above into the app's content. Run the gate,
full app checks and device/accessibility review before release.
