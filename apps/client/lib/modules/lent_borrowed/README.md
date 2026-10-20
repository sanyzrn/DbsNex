# Lent & borrowed

## 1. What it does

Lent and Borrowed have separate tabs, outstanding and settled sections, and
due/overdue wording. The current tab supplies the default direction for New.
Record money in a chosen currency or an item with integer quantity, person,
issue date, optional due date and note. Dates are absolute: typed as
`yyyy/MM/dd` (Latin, Persian or Arabic digits) or picked on the shared module
calendar — Jalali for a Persian solar-calendar reader — with today/7/14/30
presets one tap away. Partial/full returns have their own
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
Serial, coalesced writes keep the latest snapshot; back/swipe keeps it, explicit
Cancel discards it, successful Save clears it. A baseline fingerprint rejects
stale drafts after a final record changes. These records stay in this module's
store/backups and never count toward progress or balances.

Loan draft fields: `person`, `amount`, `what`, `quantity`, `issueDate`,
`dueDate`, `note` strings; `currency`, `direction`, `kind` keys; `digits`
integer; `recordId` target ID. Drafts do not create financial liabilities.
Older drafts from the offset era (`daysAgo`/`dueIn` around an ISO `anchor`)
are brought onto the calendar as the absolute dates they meant when reopened.

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
- **Dates are absolute, entered on the person's calendar.** The issue field
  starts at today; the due field is empty by default, filled by typing
  `yyyy/MM/dd` or by the shared module calendar (Jalali for a Persian
  solar-calendar reader), with today/7/14/30/none presets one tap away.
  An overdue date is simply a due day that has passed. Due before issue is
  refused; years are accepted only in 1900–2100 so a Persian year is never
  silently stored as a civil one.
- Unchanged issued/due values are kept exactly, even across midnight. Civil
  shifts use calendar construction through UTC midnights, not 24-hour durations.
  Correcting a name never moves the deadline. Civil keys remain storage-only;
  what a person reads goes through the shared Jalali-capable label.
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
item with a count. Set an optional due date — type it or pick it from the
calendar; the presets fill common deadlines in one tap. Record each partial
return and the remaining balance
updates. Mark fully returned for the remainder; delete that return to correct a
mistake. Editing preserves the deadline and history, and deletion has Undo.
Currency/type stay fixed while returns exist. Everything stays local and offline.

**فارسی:** جهت قرض‌داده یا قرض‌گرفته را انتخاب کنید و پول را با ارز خودش،
یا وسیله را با تعداد، ثبت کنید. موعد اختیاری را تایپ کنید یا از تقویم
انتخاب کنید؛ میان‌برها موعدهای رایج را با یک ضربه پر می‌کنند. هر برگشت جزئی را ثبت کنید تا باقی‌مانده به‌روز شود. برای
تسویهٔ کامل، باقی‌مانده را ثبت کنید؛ با حذف همان برگشت می‌توانید اشتباه را
اصلاح کنید. ویرایش، موعد و تاریخچه را نگه می‌دارد و حذف بازگردانی دارد.
تا وقتی برگشت ثبت شده، ارز و نوع ثابت می‌مانند. همه‌چیز محلی و آفلاین است.

## 5. Changelog

- EN: Lent & borrowed: absolute dates on the shared Jalali-capable calendar,
  international currencies with exact partial returns, stable overdue edits,
  guarded units and recoverable drafts.
- FA: قرض و طلب: تاریخ مطلق روی تقویم مشترک با پشتیبانی جلالی، ارزهای
  بین‌المللی با برگشت جزئی دقیق، حفظ موعد در ویرایش، حفاظت از واحدها و
  پیش‌نویس قابل‌بازیابی.

## 6. Platform requests

1. ~~Shared Jalali calendar picker/formatter~~ — fulfilled by the platform in
   2.1.3 (`NexModuleDateEntry`, `nexPickModuleDate`, `nexModuleDateLabel`);
   this module now uses them for every date it enters and shows.
2. ~~Export `NexTextField` for Nex's native per-paragraph note editor~~ —
   fulfilled; the module's notes use the shared `NexTextField`.
3. Optional atomic storage batch / compare-and-write for multi-record balances.
   Re-reading, guarded operations and the deletion recovery journal currently
   work wholly within the module API without a private core dependency.

## 7. Checks

Upgraded against Nex `main` `f196440` (v2.1.8) with the repository's pinned
Flutter **3.35.5** / Dart **3.9.2** on Linux. All edits stay inside
`lib/modules/lent_borrowed/` and `test/modules/lent_borrowed/`.

Commands run from `apps/client`:

```text
flutter pub get
dart format lib/modules/lent_borrowed test/modules/lent_borrowed
flutter analyze --fatal-infos
flutter test test/module_kit_test.dart -j 2
flutter test test/modules/lent_borrowed -j 2
```

Final results on this pass: analyzer **clean**; module-kit gate **40/40**;
module tests **91/91 passed** (including the Jalali pick-a-day flow, calendar
buttons, presets, absolute-date draft round-trips, refusal of dates outside
1900–2100 and before issue, Persian RTL and English LTR at text scale 2.0,
light/dark, undo and recovery journeys).

## 2.1.11 changes

- 2.1.11: optional due-date reminder on a loan, withdrawn when settled or deleted; calendar button beside date fields; one primary action on an empty page.
- 2.1.12: per-currency totals, search and filters, a page per person, shareable reminder messages in three tones.
