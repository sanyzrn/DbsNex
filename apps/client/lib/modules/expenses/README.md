# Expenses (`expenses`)

## What it does

A voluntary offline payment book: expense/income, month or all time, per-currency
totals/net, accessible category bars, filters/search, manual monthly budgets,
custom categories and confirmed reusable templates. Amount, currency, date/time,
category, merchant/source, account label and notes are entered by the person.
An incomplete payment is visible in all-time, excluded from calculations and
repairable; a missing date requires explicit selection rather than inventing one.

Transaction, budget and template editors retain raw drafts, including unfinished
amounts and choices. Back asks Keep editing / Keep draft & close / Discard.
Saving completes inside the form; failure retains text and shows an inline error.
Delete has guarded Undo; categories retain their original identity, and category/
template Undo is accessible above the open sheet. Read errors have Retry.

No bank credentials, bank sync, OCR, advice/predictions, alerts, background charges,
automatic FX, transfers or cross-module loan/expense inference. A repayment in
Lent & Borrowed does not automatically count here. Templates never charge anything.
Module records follow Nex backups/removal; offline is not a claim that core backups
never leave the device or that this module adds its own encryption.

## Records

Only this module's NexModuleStore. Stable IDs; JSON-compatible values; ISO timestamps.

| Kind | ID | Fields |
|---|---|---|
| tx | tx-<store ID>; resumed drafts keep that ID | type expense/income, amount integer minor units, currency legacy alias, currency_code, currency_exponent, date, optional category/note/merchant/account, schema 2 |
| cat | cat-<store ID> | label, schema 1; eleven defaults are localized synthesized IDs |
| budget | budget-YYYY-MM-<category or all>-<currency> | month, optional category, amount, currency + explicit code/exponent, schema 2 |
| tpl | stable store ID | label, type, amount, currency + code/exponent, optional category/note/merchant, schema 2 |
| settings | main | currency, irrUnit rial/toman, schema; unknown keys retained |
| draft | tx:new / tx:<id> / tx:template:<id>:new / tpl:new / budget:<month>:new or budget:<id> | v 1, base JSON fingerprint, fields raw strings + choices + stable recordId |
| operation | store ID | v 1, raw before-images and committed flag for recoverable writes/deletes |

~~~json
{"schema":2,"type":"expense","amount":1250,"currency":"USD",
"currency_code":"USD","currency_exponent":2,"date":"2026-10-14T12:30:00",
"category":"cat-food","note":"Entered payment"}
~~~

Legacy schema 1/missing schema is readable using a known currency's exponent.
No monetary rescaling is invented during migration. Conflicting currency aliases/
exponents, unsupported codes, bad types/amounts and impossible dates make payments
incomplete. Legacy zero payments remain readable; new payments must be positive.
Malformed auxiliary records remain stored and are excluded by their readers.
Unknown fields survive fresh edits and exact deletion Undo. Empty optional fields
are removed only when the person clears them, preserving other newly changed data.
Date/time text in drafts includes dateConfirmed for repairs.

Deleting a payment includes its edit draft. Interrupted uncommitted operations roll
back from raw before-images on read/reopen; a committed marker only needs cleanup.
Undo refuses to overwrite later edits. Replacing a budget's category/currency moves
the original identity recoverably; it does not duplicate the original budget or
silently overwrite another existing destination. Payments are never changed by this.

## Decisions

- Fourteen explicitly selectable currencies: IRR/USD/EUR/GBP/JPY/KWD/AED/SAR/TRY/
  CHF/CAD/AUD/CNY/INR. Curated offline catalogue, not every ISO currency. Exponents
  were verified on 2026-10-14 against [SIX ISO 4217 List One](https://www.six-group.com/dam/download/financial-information/data-center/iso-currrency/lists/list-one.xml),
  published 2026-09-17. JPY 0; KWD 3; other offered codes 2, including IRR.
- Stored amounts are integer minor units, 1..10^15 per new payment/template;
  budgets allow zero. 1 rial = 100 ISO minor units; 1 toman = 10 rials = 1000.
  IRR entry/display is labelled. Switching rial/toman re-expresses the exact amount.
  A currency choice is denomination, not conversion. No FX is supplied or inferred.
- ASCII/Persian/Arabic digits and period/Arabic decimal separators work. A comma
  is explicitly treated as a decimal separator; grouping, signs, exponent notation,
  NaN/infinity, excess precision and excess amount are refused. No input rounding.
- Every currency has separate expense/income/net, category totals and budgets.
  BigInt aggregate intermediates/results prevent 64-bit or web-safe-integer wrapping;
  only bounded integer amounts enter JSON. Percentage labels are integer half-up;
  progress converts a bounded integer ratio for paint only. Zero budget with no
  spending has zero progress; spending against zero shows the actual overage.
- Month buckets use the local calendar. ISO offset/UTC timestamps are converted
  to the device's local timezone; legacy naive timestamps retain written local time.
  Month lengths and relative day arithmetic use civil UTC coordinates, avoiding DST
  23/25-hour mistakes. Relative month distance is exact, not capped at 1200 months.
  Gregorian dates and years are disclosed; no fake Jalali formatting.
- Edits merge changed fields into a fresh body, retaining fresh corrections to
  untouched fields and unknown metadata; a deleted edited payment is not recreated.
  Drafts have stable IDs and are drained before the journaled save. Optional default
  currency write failure cannot turn a successfully saved payment into a duplicate.
- Operations serialize per store instance; public API has no database transaction/
  compare-and-write. Independent multi-window/external writers need platform support.
  Local journal recovery is useful without claiming global ACID guarantees.
- Currency-labelled amounts wrap at small widths; category bars have text/semantics.
  Filter/search limits the payment list; overview totals remain for the selected
  month/all-time scope. A negative net is arithmetic, not a financial warning.

## Guide

EN: Record only payments you want in this manual book. Select expense or income,
the currency and its amount, date/time and category. Verify the labelled unit;
rials and tomans are choices only for IRR. The overview shows what you entered,
separately for every currency, not your bank balance. Set a monthly category or
overall budget, including zero; unused amounts never roll forward. Filter or search
the list without changing the month's overview. Keep a draft to finish later;
failed saves retain your input. Templates prefill a payment you must confirm.
Category deletion preserves payments; Undo restores the same original category.

FA: فقط پرداخت‌هایی را که می‌خواهید در این دفتر ثبت کنید. هزینه یا درآمد، ارز،
مبلغ، تاریخ و دسته را انتخاب و واحد مبلغ را بررسی کنید. ریال و تومان فقط برای
IRR هستند. جمع‌ها برای هر ارز جدا و بر پایهٔ دادهٔ شما هستند، نه موجودی بانک.
بودجهٔ ماهانهٔ دسته یا کل را حتی صفر تعیین کنید؛ باقی‌مانده به ماه بعد منتقل
نمی‌شود. جست‌وجو و فیلتر فقط فهرست پرداخت‌ها را محدود می‌کنند. پیش‌نویس را برای
بعد نگه دارید؛ خطای ذخیره متن را پاک نمی‌کند. قالب فقط فرم را پر می‌کند و ثبت
پرداخت تأیید شما را می‌خواهد. حذف دسته، پرداخت‌ها را حذف نمی‌کند؛ بازگردانی همان
شناسهٔ قبلی را برمی‌گرداند. تاریخ ناقص را صریحاً انتخاب کنید؛ تاریخ فرضی ثبت نمی‌شود.

## Changelog

EN: Corrected exact international currency metadata, huge aggregates, Unicode
input, strict dates and month calculations. Added raw persistent drafts, visible
retry/errors, same-ID category/payment Undo and recoverable budget corrections.
Improved Nex layouts for compact screens, large text, both languages and themes.

FA: ارز و مبلغ دقیق، رقم فارسی/عربی، تاریخ و جمع‌های بزرگ اصلاح شد. پیش‌نویس خام،
خطای قابل‌مشاهده، تلاش دوباره، بازگردانی با شناسهٔ اصلی و اصلاح قابل‌بازیابی بودجه
اضافه شد. نمایش Nex در صفحهٔ کوچک، متن بزرگ، دو زبان و دو تم بهبود یافت.

## Platform requests

Public native multiline editor and shared Jalali picker/formatter. Current text
fields follow content direction; notes remain one line until the approved native
editor is exported. Gregorian labels are explicit. Optional atomic batch/
compare-and-write for independent writers; the module's local journal is the
current fallback. No bank/network/notification integration is required for the core.

## Checks

Windows/PowerShell, Flutter 3.35.5, Dart 3.9.2; current main baseline
724b999a91c5b7366fbb4d9e8f17b36a3fb16318, reviewed 2026-10-14.

~~~text
flutter test --no-pub test/module_kit_test.dart test/modules/expenses --reporter expanded
dart analyze --fatal-infos lib/modules/expenses test/modules/expenses
dart format <expenses lib/test folders>
~~~

Exact final counts and full-client results are in the phase folder's review/VALIDATION.md. Tests cover calculations, 14 currency exponents, fractional
IRR/JPY/KWD, no mixed sums, strict dates, huge totals, unknown/raw fields, correction,
rollback-after-commit fault, Undo conflicts, actual draft/read/save/template/category
journeys, reopen and isolation. Real Nex widget renders cover Persian dark/English
light and 320×480 at scale 2 with reduced motion, including the payment editor.
They are synthetic-data widget renders, not device screenshots. Native keyboard,
Android/iOS builds and TalkBack/VoiceOver need maintainer/device acceptance.

No source edits outside this module's lib/test are delivered. Registry registration
is temporary; maintainer const-registers ExpensesModule(), checks current planned
IDs and integrates Guide/Changelog separately. No Commit/Push/ZIP.
