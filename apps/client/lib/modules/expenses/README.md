# Expenses (`expenses`) — «هزینه‌ها»

## Maintenance pass (2.8.16)

A second read of the shipped module against the same brief and the same kit,
after it had been in use.

### Fixed

- **Switching rial → toman multiplied the money by ten.** The unit switch
  kept the typed digits and only changed the word, so 1,250,005 rials became
  1,250,005 tomans (12,500,050 rials) on save. The field now converts through
  `expenseAmountInput` — the parse/format pair it already owns — so the money
  is preserved exactly (1,250,005 rials → 125,000.5 tomans → 1,250,005
  rials), and a regression test pins the round trip.
- **Opening a saved payment then going Back asked “Discard this entry?”.**
  The amount field regrouped its own text on the first frame, which marked
  the form dirty. A `_writing` guard keeps those programmatic writes out of
  the dirty check; typing still guards the form.
- **A month with budgets but no payments showed the empty state.** The
  overview replaced the body, hiding budgets the person had just set. A month
  is empty only when it has neither records nor budgets.
- **A filtered list no longer shows a header total it cannot know.** With a
  search, a category or an amount range on, the day and month headers keep
  their label and drop the total; the hero still states the month's real
  spending.

### Added

- **Records by day**, each day with its own total. All time reads as months,
  newest first, with a total per month.
- **A six-month trend** above the records: this month and the five before,
  as bars scaled to the largest, with the month's own total. It uses the same
  Jalali/Gregorian month as the screen, is hidden in All time, and is
  decoration — not part of the share text or any total.
- **A month picker.** Tapping the month opens the year's twelve months in the
  person's calendar with a year stepper, plus a “This month” chip. Ends the
  arrow-by-arrow walk to Farvardin. Each cell is announced as a button with
  its selected state.
- **Last month's budgets in one tap** (“Copy last month's”) with Undo, and
  **Add a budget** inside the budget panel.
- **Repeat a payment** (`expenses-duplicate`): today's copy of an earlier
  payment, without its recurring link.
- **Rename a category you added**: the id stays, so every past payment keeps
  its category and its icon.
- **Category icons** on rows, the category filter, budgets and the categories
  sheet, from one `expenseCategoryIcon` table.
- **Persian-aware search.** Arabic/Persian yeh and kaf, hamza forms, ZWNJ,
  tatweel, harakat and Persian digits fold to one form: «یاران» finds
  «ياران», «خانه» finds «خانۀ». Folding is module-local
  (`foldExpenseSearch`) because `module_api.dart`'s export set is asserted
  exactly by `module_kit_test.dart`.

### Decisions

- **A total belongs to what it totals.** A day header says the day's spending
  only while nothing narrows the list; a filtered list says nothing it does
  not know. Grouping itself stays: the headers are still where the records
  are, only their totals leave.
- **All time is a year of months**, not one flat list.
- **A copy is a new payment.** Duplicating drops `templateId`/`period`, so
  the recurring offer still owns the month and a copy cannot make it think
  the month is done.
- **A rename is not a new category.** `renameCategory` writes the label on
  the `cat` record; the id, and with it every reference, stays.
- **Copied budgets are caps, not leftovers.** “Copy last month's” copies the
  budget amounts; what was left is not rolled forward (still an open
  question below).

### Checks

See the Checks section at the end; this pass added `audit_test.dart` (20
widget/controller tests: unit round trip, Back without a discard prompt,
budget-only month, day grouping and totals, filtered headers, trend,
month picker, copied budgets with Undo, duplicate, rename, folded search) on
top of the module's own suite.

### Limits

- The trend is six totals as bars: no axis labels, no tap target. A real
  report belongs to a Reports surface the kit does not define yet.
- Copying budgets copies caps only; carrying what was left is still open.
- Duplicating always dates the copy today; choosing its date would need a
  second sheet.
- A built-in category keeps its bundled word; only categories the person
  added can be renamed.

## Audit (2.8.4 upgrade)

What the module did before this pass, screen by screen, and what was below the
brief or the standard of `lent_borrowed`.

| # | Before | The brief or the standard | Status |
|---|---|---|---|
| A1 | Home: totals per **currency** (14 ISO codes), an overall month change, budgets, category bars, filter chips, search, records. | One Iranian book: whole rials, one total, tomans or rials said the way `lent_borrowed` says them. | done |
| A2 | Month buckets were **Gregorian**; a Jalali span hint under the title. | “A month is a Jalali month in Persian.” | done |
| A3 | Month change only overall, per currency. | Change **per category** — “groceries +18%”. | done |
| A4 | Net per currency; income existed but nothing said what is left. | Income optional, so the month can show what is left. | done |
| A5 | Templates were a generic prefill: no day, no offer. | Recurring payments kept as templates; on their day the module offers “log this month’s”; it never logs by itself. | done |
| A6 | Nothing shared a month. | Share a month as text with `nexModuleShareText`. | done |
| A7 | Search matched words; category chips filtered; no amount range. | Find a payment by words, category **or amount range**. | done |
| A8 | Defaults: food, transport, home, bills, health, fun, clothes, gifts, education, salary, other. | Categories that fit an Iranian household: groceries, rent, bills, transport, health, children, gifts. | done |
| A9 | No `summarize`, no `duesBetween` (shared rules 1 and 4). | One line per record; one function for everything falling due. | done |
| A10 | A money screen with no way to hide amounts. | Privacy: offer to hide the amounts (shared rule 8). | done |
| A11 | Entry: type, amount, currency picker, date, time, category, note, merchant, account — one wall of fields. | “A payment written down in seconds: amount, category, today by default; everything else optional.” | done |
| A12 | `SegmentedButton` for type; grouping only for a currency’s decimals. | `NexAdaptiveSegments`; grouping as typed, Persian digits in Persian. | done |
| A13 | Tests were currency-centric; no Jalali-month, recurring, share, summary or legacy-upgrade test. | Upgrade: Jalali months, rials, recurrence, sharing, one compatibility test. | done |
| A14 | README lacked the seven sections, the device checklist and open questions. | Prompt 12’s README. | done |

What was already right and was kept: raw persistent drafts and the discard
prompt, the journaled recoverable write with guarded Undo, defensive readers
that keep a malformed record visible and out of totals, the shared multiline
note editor, the shared date label and calendar button, the category sheet
with custom categories, budgets that never roll over, and `NexModuleHero`.

## Maintainer review (2.8.4)

Reviewed after merge and made available. Checked: a 2.1.x rial amount was
stored in IRR minor units (ISO exponent 2 in the old `money.dart`), so
`amount ~/ 100` is exact, and anything else stays an incomplete record;
totals are `BigInt`; the month before is the shared `NexModuleMonth.shift`.
The upgrade replaced the 2.1.x test files; what they held that the new ones
did not — a month compared across a year boundary (Farvardin with Esfand,
January with December) and totals past a 64-bit sum — is kept in
`review_284_test.dart`. Persian: the ezafe is written «هٔ» as in the rest of
the app, and «هم‌رسانی» as the app says it.

## What it does

A voluntary offline payment book for a household: write down what you paid in
seconds, and see where the month went without a spreadsheet.

- **A payment in seconds.** Expense or income, the amount (Persian or English
  digits, grouped as you type), a category, and today. The day, the clock, a
  note, the merchant and an account label sit behind one optional card.
- **The month at a glance.** What the month cost, what came in, what is left,
  spending per category, and each category against last month (“groceries
  18% more”).
- **The month you read.** A Jalali month in Persian, the Gregorian one in
  English — the app’s own calendar (`NexModuleMonth`).
- **Budgets that stay calm.** A budget per category or for everything, with
  spent, left and over by; over is stated quietly, never in red.
- **Recurring payments.** Rent, the internet, a subscription: kept as
  templates with a day of the month. On that day the module offers “log this
  month’s”, and one tap writes it. Nothing is ever written by itself.
- **Find a payment** by words, by category, or by an amount range.
- **Share a month** as plain text — the categories, the total, what is left.
- **Hide the amounts** in one tap when someone is looking over your shoulder.

No bank connection, no SMS reading, no OCR, no advice, no predictions, no
background charges, no exchange rates, no transfers. A repayment in Lent &
Borrowed does not count here; the module cannot read another module’s data.
Records follow Nex backups and removal.

## Records

Only the module’s own `NexModuleStore`. Stable ids; JSON-compatible values;
ISO timestamps. Money is **whole rials** (`docs/18-module-kit.md`, rule 2).

| Kind | Id | Fields |
|---|---|---|
| tx | `tx-<store id>`; a resumed draft keeps its id | type `expense`/`income`, `amountRial` (int), `date` (ISO 8601, local), optional `category`, `note`, `merchant`, `account`, optional `templateId` + `period` (the first civil day of the month a recurring payment settles), `schema` 3 |
| cat | `cat-<store id>` | `label`, `schema` 1; the built-in categories are not records — they come from the module’s strings (`cat-groceries`, `cat-rent`, …) |
| budget | `budget-<YYYY-MM-DD>-<category or all>` | `start` (the month’s first civil day), `amountRial`, optional `category`, `schema` 3 |
| tpl | stable store id | `label`, `type`, `amountRial`, optional `category`, `note`, `merchant`, optional `day` 1–31 and `calendar` `jalali`/`gregorian`, `schema` 3 |
| settings | `main` | `unit` `rial`/`toman`, `hideAmounts` bool, `schema`; unknown keys retained |
| draft | `tx:new`, `tx:<id>`, `tx:template:<id>:new`, `tpl:new`, `budget:<start>:new`, `budget:<id>` | v 1, base fingerprint, raw field strings, choices, stable `recordId` |
| operation | store id | v 1, raw before-images and a committed flag for recoverable writes/deletes |

~~~json
{"schema":3,"type":"expense","amountRial":1250000,
 "date":"2026-11-05T12:30:00","category":"cat-groceries","note":"نان"}
~~~

**Records written before this upgrade still open.** A 2.1.x payment stored an
`amount` in the minor units of a `currency`; the rial’s ISO exponent is 2, so
a whole-rial amount is read as `amount ~/ 100` **exactly**, once. A payment in
another currency, or one holding a fraction of a rial, is kept and shown as an
**incomplete record** — visible, repairable, excluded from totals — because no
exchange rate may be invented here. A 2.1.x budget (`month: "2026-11"`) opens
as the first day of that month; a 2.1.x template converts its rial amount the
same way. Editing one of these writes `amountRial` and drops the old currency
keys, keeping every field this version does not know.

An impossible or missing date, a bad type, a bad amount or a broken record
makes an incomplete record, never a crash and never a silent drop. Unknown
fields survive an edit; optional fields are removed only when the person
clears them. Interrupted writes roll back from their before-images on the
next read or reopen; a committed marker only needs cleanup. Undo refuses to
overwrite a later edit. Deleting a payment takes its edit draft with it.

## Decisions

- **One currency, whole rials.** The brief is an Iranian household book and
  the shared rule says “whole integers in rials, stored once”. The
  fourteen-currency catalogue of 2.1.x is therefore gone: one total, one
  budget per month, and no exchange rate anywhere. The unit (rial or toman) is
  how the number is *said*, never how it is kept; a toman is ten rials, so a
  toman amount may carry one decimal and nothing is rounded. The module is
  Soon, so this is a change to code nobody has data in; the old shapes still
  open, as above.
- **A month is the month a person reads.** `NexModuleMonth` gives the Jalali
  month in Persian and the Gregorian one in English. A budget is keyed by that
  month’s **first civil day**, so it keeps its meaning whichever calendar the
  app shows, and “budget for this month” cannot drift.
- **Recurring, never automatic.** A template with a `day` is recurring. The
  day is counted in the calendar it was set in, and that calendar is stored
  with it, so “the 5th” keeps meaning the 5th of that month after a language
  change. The home offers the payment from its day until the month is written
  down; a payment carries `templateId` and `period`, which is exactly what
  says “this month is done”. One tap logs it, with Undo; nothing is scheduled
  and nothing is written without the tap. No reminders are requested by this
  module (the brief asks for an offer on the day, not a notification).
- **Amounts are parsed strictly.** Latin, Persian and Arabic digits; grouping
  separators and spaces are layout; one decimal separator, at most the unit’s
  own digits; no signs, letters, exponent notation, leading zeros or
  over-precision. The field groups while typing and keeps the caret, copied
  from `lent_borrowed/money_input.dart` with the same calls, as the kit asks.
  The most a record can hold is 10^15 rials.
- **Budgets never roll over.** Zero is a valid budget; spending against zero
  shows the actual overage. Changing a budget never touches payments.
- **Income is optional and says what is left.** The month shows spent,
  received, and left (received − spent). A negative left is arithmetic, said
  plainly, never a warning.
- **Each category against last month.** The percent exists only when the month
  before had spending in that category; a percentage of nothing is not shown.
- **Sharing is text.** The month’s categories, total, income and left, in the
  chosen unit and the language of the page, through `nexModuleShareText`.
  There is no image sharing in the kit; see Platform requests.
- **Privacy.** The money screen offers to hide the amounts (its own
  `hideAmounts` setting, shared rule 8) and replaces them with dots. Health
  data is not here, so `NexSecureWindow` is not used.
- **Shared shapes.** `duesBetween` is `ExpenseSchedule.duesBetween(from, to)`,
  built from the templates and the logged months, and the controller exposes
  it as the one function the home and (later) the shared calendar call.
  `summarize` is in `expenses_summary.dart`; `ModuleDue` and `ModuleSummary`
  are copied there with the exact fields of `docs/18-module-kit.md`, as
  `words_summary.dart` does, until the kit provides them. The summary line
  uses the person’s own words and Latin figures, because the record reaches
  it without a language; it is marked private (money).
- **Legacy ids and the built-in categories.** The older category ids stay, so
  a payment written with `cat-food` keeps its word; groceries, rent and
  children join them.
- **Unchanged by design:** no bank/SMS/network, no advice, no automatic
  transfers, no cross-module inference.

## Guide

EN: Choose Expense or Income, type the amount (tomans or rials — the switch
re-words the same money), and a category; today is already the date. Open “Add
details” only when you want to change the day or add a note. The overview is
what you entered this month, not a bank balance; each category shows its
change against last month, and the six-month bars put this month beside the
five before it. Tap the month for the year's grid, or “This month” to come
back. Records are grouped by day with each day's total; All time reads month
by month. Set a monthly budget for a category or for everything — “Copy last
month's” brings the caps over, Undo takes them back, and over is information,
not a warning. A template with a day (rent, the internet) is offered on that
day: one tap writes that month, and Undo takes it back. Repeat a payment from
its row, rename a category you added, find a payment with the search field
and the amount range (Persian spelling is forgiven), share the month as text,
and hide the amounts with the eye when someone is looking.

FA: هزینه یا درآمد را انتخاب کنید، مبلغ را بنویسید (تومان یا ریال؛ تغییر واحد
همان پول را با واژه‌ی دیگر می‌گوید) و دسته را بزنید؛ تاریخ امروز است. «جزئیات
بیشتر» را فقط برای تغییر روز یا یادداشت باز کنید. نمای ماه همان چیزی است که
وارد کرده‌اید، نه موجودی بانک؛ هر دسته تغییرش را نسبت به ماه قبل نشان می‌دهد و
نمودار شش‌ماهه این ماه را کنار پنج ماه قبل می‌گذارد. ماه را بزنید تا جدول سال
باز شود، یا «این ماه» را بزنید تا برگردید. پرداخت‌ها به تفکیک روز با جمع هر روز
می‌آیند و «همهٔ زمان‌ها» ماه به ماه خوانده می‌شود. بودجه‌ی ماهانه برای یک دسته یا
همه بگذارید — «کپی از ماه قبل» سقف‌ها را می‌آورد و بازگردانی برمی‌گرداند؛ بیشتر
شدن، اطلاع است نه هشدار. قالبی که روز دارد (اجاره، اینترنت) در همان روز پیشنهاد
می‌شود: یک ضربه همان ماه را می‌نویسد و بازگردانی برمی‌گرداند. از خود ردیف،
پرداخت را تکرار کنید، نام دسته‌ای که ساخته‌اید را عوض کنید، پرداخت را با
جست‌وجو و محدوده‌ی مبلغ پیدا کنید (املای فارسی بخشیده می‌شود)، ماه را
به‌صورت متن همرسانی کنید و با چشم، مبلغ‌ها را پنهان کنید.

## Changelog (2.8.4)

EN: Expenses is now an Iranian household book: whole rials with a rial/toman
switch and grouping as you type, a Jalali month in Persian, each category’s
change against last month, income that shows what is left, monthly budgets
that stay calm, recurring payments (rent, internet, a subscription) offered on
their day and written with one tap, categories for groceries, rent and
children, search by amount range, sharing a month as text, hidden amounts in
one tap, and a payment form that asks only for the amount, the category and
today. Payments and budgets from earlier versions still open and keep their
money.

FA: «هزینه‌ها» حالا دفتر یک خانه‌ی ایرانی است: مبلغ به ریالِ کامل با کلید
ریال/تومان و جداکننده‌ی رقم هنگام تایپ، ماه جلالی در فارسی، تغییر هر دسته
نسبت به ماه قبل، درآمد و باقی‌مانده، بودجه‌ی ماهانه‌ی آرام، پرداخت‌های
تکرارشونده (اجاره، اینترنت، اشتراک) که روزِ خودشان پیشنهاد و با یک ضربه ثبت
می‌شوند، دسته‌های خوراکی، اجاره و فرزند، جست‌وجو با محدوده‌ی مبلغ، همرسانی ماه
به‌صورت متن، پنهان‌کردن مبلغ‌ها با یک ضربه، و فرمی که فقط مبلغ، دسته و امروز را
می‌پرسد. پرداخت‌ها و بودجه‌های نسخه‌های قبل باز می‌شوند و پولشان را حفظ می‌کنند.

## Platform requests

- **Image sharing** for a month (a picture of the breakdown for a family
  group). Meanwhile the month is shared as text.
- **A recurring source in the app’s Recurring page and the “due radar”.** The
  shape is ready (see Later); a platform reader can build `ModuleDue`s from it
  through `duesBetween`.
- **A notification on the day** a recurring payment falls due, through the
  shared reminder controls. Today the offer is on the module’s home only; no
  notification is scheduled, and nothing is written without the tap.
- **Atomic compare-and-write** for independent writers. The module’s own
  journal covers a single writer; multi-window edits still need platform
  support.

## Checks

Linux, Flutter 3.47.9 (stable, Dart 3.13.7), maintenance pass on base
`cac07ab3` (v2.8.16), 2026-11-23.

~~~text
dart format lib/modules/expenses test/modules/expenses   # 0 changed
flutter analyze --no-pub --fatal-infos lib/modules/expenses  # No issues found
flutter test --no-pub test/modules/expenses              # 112 passed
flutter test --no-pub test/modules/expenses test/module_kit_test.dart \
  test/module_shared_rules_test.dart test/module_glance_test.dart \
  test/ui_consistency_test.dart test/whats_new_test.dart \
  test/version_test.dart test/update_sheet_test.dart     # 260 passed
~~~

The maintenance pass added `audit_test.dart` (20 tests): the unit round trip
that must not change the money; opening a saved record and going Back without
a discard prompt while typing still guards; a month with budgets and no
payments; day grouping and per-day totals; a filtered list dropping the
header total; the six-month trend; the month picker; copied budgets with
Undo; duplicate dropping the recurring link; rename keeping the id; folded
search for Persian yeh/kaf and ZWNJ.

The earlier review, Linux, Flutter 3.47.9, base `e3edff3f`, 2026-11-18. The
whole suite also reported one unrelated `photo_capture_policy_test.dart`
timeout while the runner was suspended; it passes alone
(`flutter test test/photo_capture_policy_test.dart` → 4 passed).

~~~text
dart format lib/modules/expenses test/modules/expenses   # 0 changed
flutter analyze --fatal-infos                            # No issues found
flutter test test/module_kit_test.dart \
  test/module_shared_rules_test.dart test/modules/expenses -j 4   # 191 passed
flutter test -j 4                                        # 4131 passed, 4 skipped
~~~

The module’s tests cover: strict rial parsing in three digit scripts with
grouping and bounds; grouping-while-typing and the caret; the toman’s tenth;
totals, income and left; month membership for Gregorian and Jalali months;
each category’s change (and no percent without a previous month); budget
standing, overage and zero; filters by words, category and amount range;
recurring due dates including 31-day months, Esfand 29/30, a Jalali day and
the “already written” flag; the summary line; saving, correcting with unknown
fields kept, legacy conversion once, deleting with exact Undo, budgets moving
with their category, the one-tap monthly log (twice refused), the two
settings, a failed read and an interrupted write; the screen’s empty state,
seconds-long entry, Persian digits, income and left, correcting, deleting with
Undo, month navigation, filters, budgets, the recurring offer (and none before
its day), hiding amounts, templates with a day, share text in both languages,
a failed read, an incomplete record, Persian dark at 320×480 with 2× text, and
the upgrade test that opens 2.1.x records and checks nothing was lost.

Screenshots in `review/`: `expenses_home_en_light.png`,
`expenses_home_fa_dark.png`, `expenses_editor_en_light.png`,
`expenses_editor_fa_dark.png`. They are widget renders over synthetic data,
not device screenshots.

## Device checklist

1. Open Expenses with nothing saved: the empty state and its one button.
2. Add an expense with the Persian keyboard: digits appear as typed, grouped;
   switch rial/toman and check the number does not change, only its words.
3. Save with only an amount and a category: the record shows today.
4. Add income, then check “Left” says received − spent.
5. Switch the language to Persian: the month is Jalali; move back a month and
   forward, including Esfand (29/30 days).
6. Set a category budget, spend past it, and check the quiet “over by” line.
7. Make a template with a day of the month; come back on/after that day and
   use “log this month’s”; check it appears once, and Undo takes it back.
8. Search by a word, a category and an amount range.
9. Share a month and read the text in a messaging app.
10. Hide the amounts, then show them again.
11. Kill and reopen the app: the draft you left, the unit, the hidden state
    and the records are as you left them.
12. Back up and restore, then remove the module with “keep data” and add it
    back.
13. Dark and light, text scale 2.0, and a small phone: nothing clipped.

## Later (described, not built)

The recurring payments are ready to feed the app’s Recurring page and a “due
radar”. A template is the record kind **`tpl`**:

~~~json
{"label":"اجاره","type":"expense","amountRial":120000000,
 "category":"cat-rent","day":1,"calendar":"jalali","schema":3}
~~~

`day` (1–31, clamped to the month’s length) and `calendar` are the recurrence;
`ExpenseSchedule.duesBetween(from, to)` turns every recurring template into
`ModuleDue`s — `recordKind: "tpl"`, `recordId`, `at` (local midnight),
`title` (the template’s label), `kind: "expense-recurring"`, `amountRial`
(negative for an expense, positive for income), `done` (this month already has
a payment with the same `templateId` and `period`), `private: true` — with a
stable id `tpl-<template id>-<month’s first day>`. A platform reader can use
that function unchanged; nothing in the module needs to move for it.

## Open questions

- Is toman the right default unit for a fresh install, or should the module
  start on rials and let the person switch?
- Should a month follow the app’s calendar setting (as now), or always be
  Jalali even in an English interface?
- When a recurring payment’s day is set in one calendar and the app switches
  to the other, is keeping the original calendar (as now) the right answer, or
  should “the 5th” always mean the 5th of the month currently shown?
- Should budgets be per month only (as now, no rollover of what is left), or
  should the left part of a budget be carried into the next month — copying
  the caps is built, but moving money is not?
- Is one overall budget plus category budgets the right shape, or should a
  category budget be capped by the overall one in the arithmetic?
- Should a legacy payment in a foreign currency be offered a one-tap “convert
  to rials at today’s rate I type myself”, instead of staying incomplete?
- Should sharing include the merchants and notes, or only categories and
  totals (as now)?
