# Gold Check (`gold`)

## What it does

An offline, auditable calculator for **new gold jewelry**. Enter net gold
mass (grams with three decimals / soot), optional gross mass, item purity,
rate and its reference purity, making charge (% / per gram / fixed / mixed),
profit, VAT, optional commission, extras and the seller's quote. The receipt
shows each rounded line, conversion, tax base, total and signed difference.
The rial/toman display switch never changes stored values or input units:
money inputs are explicitly toman; 1 toman = 10 rials.

Choose the profit base and whether commission joins VAT **explicitly**.
Read the formula and invoice checklist; select the breakdown to copy using
the system's selection menu. Save a title/shop/date/note; edit the same
estimate; start a new estimate; browse, compare and delete with Undo.
Comparison identifies both quotes and warns on different specifications;
the cross-spec difference is suppressed. Drafts survive back/navigation and
restart, including invalid unfinished input. Clear draft discards a fresh form.

No live prices, currency conversion, legal invoice certification, second-hand
gold/coins/bullion assumptions, background alerts.

## Records

Kind **`quote`**, stable store-generated ID, schema 2 for new snapshots:

```json
{"schema":2,"title":"Ring","shop":"Shop","savedAt":"2026-10-13T12:00:00",
"quoteDate":"2026-10-13","notes":"Typed note","weightMg":3000,
"grossWeightMg":0,"finenessPpt":750,"rateCentiPerG":1000000000,
"rateRefPpt":750,"makingMode":"percent","makingPercentBp":1000,
"makingPerGramCenti":0,"makingFixedRial":0,"profitBp":700,"vatBp":1000,
"profitBase":"metalAndMaking","commissionTaxable":true,"commissionRial":0,
"extras":[],"shopQuoteRial":0,"snapMetalRial":300000000,
"snapMakingRial":30000000,"snapProfitRial":23100000,
"snapCommissionRial":0,"snapVatBaseRial":53100000,"snapVatRial":5310000,
"snapExtrasRial":0,"snapTotalRial":358410000}
```

All amounts and snapshots are integer rials; rates are centi-toman/g,
mass milligrams, percentages basis points. `extras` holds `{label,amount}`
with integer rials; an amount of zero is a saved zero, kept through
reading and editing. `profitBase` is `metalAndMaking`, `metalOnly` or
`services` (making + commission). Existing schema-1 records default to
`metalAndMaking` and taxable commission; snapshots are never recalculated
on read. Numeric metadata rejects NaN/infinity/fractions/negative/oversized
values; absent fields use documented constructor defaults, not current law.
Zero `shopQuoteRial` means no entered quote; zero gross means no gross mass.
Unknown fields survive edit (merged with fresh raw body) and deletion Undo.

Kind **`draft`**, ID `quote:new` or `quote:<id>`, `{v:1,base,fields}`.
`base` is the JSON fingerprint of the original quote or `{}`. `fields` holds
raw strings `weight,gross,rate,makingPercent,makingPerGram,makingFixed,profit,
vat,commission,shopQuote,title,shop,quoteDate,notes`, typed choices
`fineness,rateRef,mode,profitBase,commissionTaxable`, `extras:[{label,amount}]`
with raw strings, and `recordId`. Stale edits and already-saved new checkpoints
are ignored. A failed cleanup may leave `{v:1,discarded:true}`. Closing waits
for the latest serial checkpoint; failed writes retry once and remain editable.
Successful Save clears the checkpoint and continues under the saved ID.

Kind **`operation`**, ID `quote:<id>`, `{v:1,records:[{kind,id,body}]}` is a
temporary recovery journal for quote + edit-draft deletion. Interrupted
deletes restore their exact bodies before the next list read. Undo restores
the same IDs, snapshots, unknown fields and related draft; store-managed
`updatedAt` changes. No transaction API is assumed.

## Decisions

- Reference default: editable profit 7%; editable VAT 10%, visibly qualified
  as the 1405 reference. The manual calculator does not verify invoice legality.
  On 13 October 2026 the prompt's [dated Tasnim report](https://www.tasnimnews.ir/fa/news/1405/02/04/3573672/نرخ-مالیات-بر-ارزش-افزوده-طلافروشان-در-سال-1405)
  and its July update were rechecked. An authoritative tax-site text could
  not be retrieved; this is a reference assumption, not a certified ruling.
- Reference formula: metal = net mass × purity-adjusted rate; making follows
  the chosen method; profit = chosen base × entered %; VAT = % × (making +
  profit + qualifying commission). Metal stays outside this VAT base. Extras
  are separately priced; their tax treatment is **not modeled**.
- Exact example: 3 g × 10,000,000 toman/g; making 10%, profit 7% on metal +
  making, VAT 10% → **35,841,000 toman / 358,410,000 rials**.
- BigInt intermediates; each monetary line rounds nearest rial, halves away
  from zero; mixed making components round separately. Rates convert by the
  visible purity ratio, rounded to centi-toman/g before pricing mass.
- All parsed scaled values and persisted monetary totals fit `2^53-1`.
  Per-field caps still apply; an excessive combination is rejected, never
  wrapped or clamped. A percentage on a rounded-zero estimate is unavailable,
  while the signed monetary difference remains visible.
- Typed Latin/Persian/Arabic digits and `.`/`٫` work. Malformed/negative and
  excessive precision are rejected; empty optional charges mean zero.
  Commas remain rejected to avoid guessing decimal vs grouping conventions.
  Reopened fields use ungrouped, symbol-free exact text.
- The quote day is entered as civil `YYYY-MM-DD` (Persian digits normalize)
  or picked from the shared module calendar, which writes the same civil
  day into the field. Every date a person reads — the detail sheet, both
  comparison columns, the receipt breakdown, the «Saved …» line's absolute
  day — goes through the shared module date label, so the person's chosen
  calendar (Jalali for a Persian reader) and its digits show it while
  storage stays civil ISO. Relative day math uses UTC civil days after
  converting instants to local time; the shown day is a local civil day,
  never a UTC instant; future days are not described as today.

## Guide

**English.** Gold Check estimates new jewelry using the numbers you enter.
Use net gold weight, choose the item's purity and the rate's reference purity,
then enter making, profit and VAT. The default profit base is gold + making;
change it explicitly when the invoice uses another base. Match commission's
tax treatment yourself. The receipt shows every line and a difference to verify,
not a judgment about the seller. Save each estimate with its date; saved rates
stay historical. Compare matching specifications and ask the shop to itemize
net weight, purity, rate basis, making, profit, commission, VAT and extras.

**فارسی.** طلاسنج قیمت طلای نو را با عددهایی که خودتان وارد می‌کنید تخمین
می‌زند. وزن خالص طلا، عیار قطعه و عیار مبنای نرخ را مشخص کنید و اجرت، سود و
مالیات را بنویسید. پیش‌فرض سود از ارزش طلا و اجرت حساب می‌شود؛ اگر فاکتور مبنای
دیگری دارد، صریحاً انتخابش کنید. مالیات کارمزد را هم با فاکتور تطبیق دهید.
رسید، هر ردیف و «اختلاف قابل بررسی» را نشان می‌دهد، نه حکمی دربارهٔ فروشنده.
تخمین را با تاریخ ذخیره کنید تا نرخ‌های همان روز بمانند. برای مقایسه مشخصات
یکسان را انتخاب کنید و تفکیک وزن خالص، عیار، مبنای نرخ، اجرت، سود، کارمزد،
مالیات و اقلام جداگانه را از فروشگاه بخواهید.

## Changelog

**English.** Gold Check now preserves historical inputs when editing, updates
the receipt immediately after picker changes, offers explicit profit/tax bases,
uses exact large-number arithmetic, and recovers drafts and complete Undo data.
The quote day can now be picked from the shared calendar — Jalali for a Persian
reader — and every date shown reads in the person's own calendar and digits;
the empty saved list offers the way back to the calculator.

**فارسی.** طلاسنج اکنون ورودی‌های تاریخی را هنگام ویرایش حفظ می‌کند، رسید را
با تغییر انتخاب‌ها فوراً به‌روز می‌کند، مبنای سود و مالیات کارمزد را صریحاً
قابل‌انتخاب کرده و محاسبات دقیق، پیش‌نویس و بازگردانی کامل داده دارد. روز
تخمین را می‌توان از تقویم مشترک برگزید — برای خوانندهٔ فارسی، تقویم جلالی — و
هر تاریخی که نشان داده می‌شود در تقویمِ خودِ فرد و با ارقام آن خوانده می‌شود؛
فهرست خالی تخمین‌ها هم راه بازگشت به ماشین‌حساب را پیشنهاد می‌کند.

## Platform requests

1. **Fulfilled** — Nex's native multiline editor is exported through
   `module_api.dart` (`NexTextField`); the save sheet's note uses it, and
   every one-line field states its direction (`NexAutoDirection`, or an
   explicit `textDirection` for numbers and dates).
2. **Fulfilled** — the shared Jalali picker/formatter. The save sheet's
   quote date is wrapped in `NexModuleDateEntry`: typing civil `YYYY-MM-DD`
   stays, and the calendar button picks a day in the person's own calendar
   and writes the same civil day. Every date a person reads goes through
   `nexModuleDateLabel` (`gold_dates.dart`); the old Gregorian labels are
   retired in both languages; storage stays civil ISO.
3. Optional atomic batch / compare-and-write for record changes. The current
   deletion journal and fresh reads are an honest local fallback.
4. Optional approved direct clipboard helper or consent-based price feed.
   Selection-menu copy is available; no live feed is implemented.

## Checks

Linux, Flutter 3.35.5 / Dart 3.9.2, on the current Nex tree:

```text
dart format lib/modules/gold test/modules/gold     # 0 changed
flutter analyze --fatal-infos                      # No issues found
flutter test test/module_kit_test.dart -j 2        # 40 passed
flutter test test/modules/gold -j 2                # 97 passed
```

Persian RTL / English LTR, light/dark, large text, store isolation,
edit/history, raw Undo and draft navigation are tested; the shared Jalali
entry (pick a day, land in field and storage as the same civil day) and
the calendar-labelled display of every stored day are covered by
`test/modules/gold/gold_dates_test.dart`. Both string maps hold the same
161 keys, with no bidi control characters in the Persian half.
Android builds and device/TalkBack checks are not represented by host
tests. Maintainer: const-register `GoldModule()`, retire planned `gold`,
incorporate Guide/Changelog and run release checks before activation.

## From a budget, making share, copy (2.1.13)

- **From a budget** (the savings icon): the budget, in toman, becomes the
  heaviest net weight whose estimate stays within it, using the rate, purity,
  charges, profit and VAT already in the form. The estimate never falls as the
  weight grows, so the answer is found by halving between 1 mg and the weight
  cap, with every line rounded exactly as the receipt rounds it — one
  milligram more is over the budget. A fixed making charge or fixed extras
  make plain division wrong, which is why it is not divided. The gross weight
  and the seller's quote do not take part. 0 means even 1 mg is over budget.
  «Use this weight» puts the answer in the form. A display of a calculation;
  nothing is saved by it.
- **Making share:** for a per-gram, fixed or mixed charge the receipt says
  what share of the metal value it comes to («the trade's percent»).
- **Copy the estimate** puts the breakdown lines on the clipboard (the lines
  can still be selected one by one).
