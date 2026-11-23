# Asset book · دفتر دارایی

## What it does

An offline ledger for gold by weight, Iranian coins, foreign currency and
named assets, available since 2.8.4.

- **Covered book.** On Android, the book acquires `NexSecureWindow` before
  any data can be revealed. A failed acquisition leaves the book covered.
  Opening the screen, going to the background, and tapping the eye return
  it to a cover with no names, places, amounts or counts. This also covers
  an open editor and retains its input.
- **Holdings.** A separate row for each purchase records quantity, purchase
  date, paid unit price and custody. Home, bank box, named platform and
  other labels help locate the entry without displaying those details on
  the dashboard. Lots of one asset sit together, oldest first, however
  often they are edited. Each valued lot shows its dated price, age and
  estimated gain or loss with a percentage; a missing price opens the price
  sheet for that asset directly.
- **Prices.** Manually enter today's or an earlier price and keep all
  observations. The picker offers 18k gold, every standard coin and the
  currencies Iranians quote most — before the asset is held. Each price
  says how old it is; an old one is flagged and offered for a one-tap
  refresh. A price dated in the future stays in the history, with a
  warning, and never values the book.
- **Value in gold and dollars.** The same priced subtotal is shown in rials
  or tomans, in grams and mithqals of 18k gold, and in USD. The two
  conversions display their benchmark dates. Coverage shows how many
  holdings have an eligible rate. With partial coverage the heading says
  “Value of priced holdings.”
- **Where the value sits.** When more than one kind is priced, a share bar
  and one line per kind answer “how much of this is gold?” without adding
  lots by hand. Four or more holdings can be filtered by kind.
- **Goals.** Set any number of named gold targets. Progress comes from net
  weight and fineness, shown as a percentage and in grams; the amount
  remaining stays meaningful even while prices are missing. The goal editor
  also says the target in mithqals.

## Audit (2.8.18)

The record format did not change. This pass fixed what the book said and
what it made people do around the numbers.

| Finding | Effect | Change |
| --- | --- | --- |
| A price dated in the future vanished from the price screen | It stayed stored but could not be seen or corrected; a date picker never allowed it, so only older records or hand-edited data were affected | `Valuation.history` now keeps every observation; only prices up to today value the book, and the future one is shown with a warning and remains editable |
| The price picker offered only gold, USD and what was already held | A person could not write down today's euro or a coin before buying it | `priceCatalogue` builds the full list: 18k gold, every standard coin, the common currencies and everything in the person's own book |
| Editing a lot moved it to the top | The page reordered under the person after every save, so lots of one asset were scattered | One stable order by kind, asset and purchase day; the store's save order no longer reaches the screen |
| A scroll followed by a reload could crash an open details tile | `ExpansionTile` inside the keyed list read the list's saved scroll offset as its own open/closed state | Each lot's details tile has its own `PageStorageKey` |
| Nothing said a price was old | With inflation, a month-old total read like today's | Price age in words, a stale marker after 7 days, and a single refresh prompt |
| An unpriced lot was only a chip | Its cost was recorded but its value silently missing | A prompt names the count, explains the exclusion and opens the first price sheet |
| No mix, no filter, no gain percentage | “How much is gold?” and “is this lot up?” meant mental arithmetic | Share bar and rows, kind filters, and gain/loss percentages on the total and each lot |
| Gold could only be typed as a thousandth fineness | People say 18 karat, and pieces of different purity are hard to compare | Karat presets (24, 22, 21, 18, 17, 14, 9) and a live 18k-equivalent weight; mithqal beside grams |
| One generic error under a long form | “Check the amount and required fields” pointed at no field | Specific errors beside the field; the purchase date and custody stay behind one optional-details button for a new lot |
| Delete asked only “Delete this entry?” | A person could not tell whether the price history or the holding would go | The dialog names what is removed and what stays; the destructive action is the error colour |
| The unit control was an unlabelled swap icon | Toman or rial was not visible in the app bar | The current unit is a labelled button with “Show in rials/tomans” |
| A second price for the same day was silent | The newer save silently won the tie | The price sheet says a price for that day exists and that saving makes this the newest for the day; the earlier observation is kept |

Also: the damaged-record notice is a proper panel rather than plain text,
the screen reloads when its records change underneath it (backup restore,
Undo, the quick view), the empty book is a three-step starting point with
one button, and a custom asset's name says that prices match by that name.

## Maintainer review (2.8.4)

Registered (`nexModules`, hue 112 — a money green between Habits and Price
Lens), reviewed and made available. Checked: whole-rial money with `BigInt`
sums, gold valued as 18k rate × net grams × fineness ⁄ 750, edits keep
unknown fields and refuse a conflicting body, the cover holds the secure
window. Changes: the Persian speaks as the rest of Nex does («شما»: «دوباره
تلاش کنید», «دفتر پوشیده است»); a currency is named («دلار آمریکا», «یورو»
for the common ones, else its code) in its title and the picker, and its
amount carries its code («۴۵۰ USD»).

## Records

All data is stored with `NexModuleStore` in the module's own local storage.
The 2.8.18 audit added no fields and no migration.

| Kind | Version and fields |
| --- | --- |
| `holding` | `v: 1`, `type/code/name: String` (identity below), `bought: ISO local civil-day timestamp`, `costPerUnitRial: int`, `fineness: int` (parts per thousand, 750 for non-gold), `custody: home/bank/platform/other`, `location: String`. Physical gold stores `quantity: int` in mg. Coins and named other assets store whole units. Foreign holdings store `amount: int` in ISO minor units and `currency: String`. |
| `quote` | `v: 1`, `type/code/name`, `date: ISO local civil-day timestamp`, `unitRial: int`. Gold price per 18k gram. Coin, foreign currency and other prices per full unit. |
| `goal` | `v: 1`, `title: String`, `targetMg: int` in milligrams of 18k-equivalent physical gold. |
| `draft` | Shared form-draft envelope and original-body fingerprint. Includes text fields, kind selections, local civil day, unit, stable record ID for retry and whether the optional purchase/storage fields were open. No financial projections read draft rows. |

Holding and quote identity is the same asset family and variant. Standard
coins have dedicated codes. Foreign currencies use the copied offline ISO
minor-unit table and quote prices in rials per one major unit. For custom
assets, the entered name identifies the price series after normalizing
spaces, case and Persian/Arabic kaf and yeh. A custom coin and another
asset of the same name remain separate. Renaming a custom holding can
point it at a different quote history; the editor says prices match by the
name. Editing preserves fields the module does not own and fails on a
conflicting stored body. Unreadable and future-version rows are preserved
with a warning. A future-dated price is valid data, stays in history and
does not value the book.

## Decisions

- **Prices in familiar units.** The [TGJU market board](https://www.tgju.org/tv/)
  separates Iranian coin types and quotes 750 gold per gram. The
  [TGJU coin reference](https://www.tgju.org/coin) describes the Emami and
  old-design distinction. The mithqal is the market's 4.6083 g weight.
  These sources informed labels and units. The module contains no sample
  market rates or network logic.
- **One comparable metal rate.** 18k rate × net grams × fineness / 750.
  The price paid per actual gram can include costs the owner chose to
  include. This estimates metal value without making charges, fees, stones
  or coin premiums inferred from weight. Coins use their own typed rates.
- **Exact money.** Paid price and quotes are whole rials. Toman is the
  default presentation and entry unit. BigInt intermediates keep products
  and sums exact. Each lot rounds half up to the nearest rial for both cost
  and value; the dashboard sums those same displayed lot values. Equivalent
  results round to milligrams, milli-mithqals and USD cents for display.
- **Incomplete coverage.** Quotes from the future and quotes earlier than
  the purchase do not value a lot. The latest date wins; same-day
  corrections use storage update time, then ID to break ties. An unpriced
  lot is excluded from both the estimate and its matching cost total.
  Benchmark prices carry their own dates. The gold target is based only
  on held metal normalized to 18k; coins and price movements do not count.
- **Freshness.** A price is called old at 7 days. The threshold is a nudge,
  not a rule: the dated price and its age are always shown, and nothing is
  fetched or guessed. One prompt refreshes the unpriced lot first, then the
  oldest priced rate, so the book never nags with several notices at once.
- **Privacy scope.** `NexSecureWindow` controls Android window capture on
  entry through exit, including editor sheets. The cover hides names,
  amounts, numbers and storage labels while the app is inactive. The book
  uses the normal Nex storage and backup policy. Confirm capture and
  recents behavior on a physical Android phone before a device release.
- **References.** Copied the shared-specified money and draft references
  from `lent_borrowed` under the original filenames and calls, plus their
  local numeric and unit helpers. The foreign selector omits IRR and places
  lira among the common options. The amount field retains invalid pasted
  signs and excess decimal separators/precision for validation. Gold
  Check's integer and purity-ratio approach informed the small independent
  valuation, with no Gold Check imports.

| Shared rule | Implementation |
| --- | --- |
| Dates and calendar | Shared calendar picker and date formatting. Persian entry/display uses Jalali. Local civil-day timestamp storage. Pure empty `duesBetween` because recorded dates are historical and goals undated. |
| Money | Whole rials, toman/rial reference formatting and Persian digits. Foreign quantities in ISO minor units. |
| People | This book stores no counterparties. Custody labels describe places or accounts. |
| Summary | Pure `summarize` returns private display identity without numeric or custody fields. |
| Record compatibility | Defensive parsing. Edits merge unchanged raw fields and reject a conflicting source. Undo restores the exact row. |
| Saving and Undo | Shared merge-safe draft guard, stable ID, Nex banner Undo for each deleted entry. |
| Reminders | No scheduled event in the brief. Historical dates never generate alerts. |
| Sharing and hiding | Whole-book cover and secure window. Private financial entries have no sharing control. |
| Shared look | Nex hero, panels, typography, adaptive segments and transition, shared sheet, `NexMoreDetails`, date picker, dialogs and overlay. |

## Guide

**English.** Reveal the book and add the first holding: its kind, amount and
the price you paid. The purchase date, custody and label sit under **Purchase
and storage**; today and home are the defaults. Enter the latest price you
have for that asset under Prices. For the benchmark comparison, add the 18k
gram and USD rates. Each price says how old it is; after a week the book
offers a refresh. Gold can be entered by karat, and the editor shows its 18k
equivalent. The book shows the value split by kind and, for a long book,
filters it. Set a gold weight target under Goals. The eye covers the book at
any time.

**فارسی.** دفتر را باز کنید و اولین دارایی را ثبت کنید: نوع، مقدار و قیمتی
که پرداخت کرده‌اید. تاریخ خرید، محل نگهداری و برچسبش زیر «خرید و نگهداری»
است؛ پیش‌فرض امروز و خانه است. در «قیمت‌ها» آخرین قیمتی را که دارید با تاریخ
وارد کنید. برای دیدن معادل ارزش سبد، نرخ هر گرم طلای ۱۸ عیار و هر دلار را هم
ثبت کنید. هر قیمت می‌گوید چند روز پیش ثبت شده و پس از یک هفته دفتر
به‌روزرسانی‌اش را پیشنهاد می‌دهد. طلا را با عیار وارد کنید؛ معادل ۱۸ عیار
همان‌جا دیده می‌شود. دفتر ترکیب ارزش را نشان می‌دهد و دفتر بزرگ را بر اساس
نوع فیلتر می‌کند. در «هدف‌ها» وزن طلای دلخواه را بگذارید و با دکمهٔ چشم هر
وقت خواستید دفتر را بپوشانید.

## Changelog

**2.8.18 — English.** The Asset book now shows where the value sits, filters
a long book, reads gold in grams and mithqal, and says how old each price
is with a one-tap refresh. Gold karat presets show the 18k equivalent as
you type, errors point at their field, and any common coin or currency can
be priced before it is held. A future-dated price is shown with a warning
instead of disappearing.

**2.8.18 — فارسی.** دفتر دارایی حالا ترکیب ارزش را نشان می‌دهد، دفتر بزرگ را
فیلتر می‌کند، طلا را به گرم و مثقال می‌خواند و می‌گوید هر قیمت چند روز پیش
ثبت شده است — با به‌روزرسانی یک‌لمسی. عیارهای رایج معادل ۱۸ عیار را همان‌جا
نشان می‌دهند، خطاها کنار همان فیلد می‌آیند و قیمت هر سکه و ارز رایج را پیش از
خرید هم می‌توان ثبت کرد. قیمتی که تاریخش در آینده است دیگر ناپدید نمی‌شود و
با هشدار نمایش داده می‌شود.

**2.8.4 — English.** Added the private Asset book with dated valuations,
gold and USD comparisons and physical gold goals.

**2.8.4 — فارسی.** دفتر خصوصی دارایی با قیمت‌های تاریخ‌دار، معادل طلا و دلار و
پیشرفت هدف طلای وزنی اضافه شد.

## Platform requests

- Live quotes would require a platform-owned, opt-in source, user-approved
  units and timestamps, and explicit labeling. The module is complete with
  manual prices; future integration must preserve manual history and the
  distinction between entered and retrieved prices.

## Checks

Run from `apps/client` with the repository's toolchain (Flutter 3.47.9):

```text
flutter analyze --no-pub --fatal-infos lib/modules/assets test/modules/assets
flutter test --no-pub test/modules/assets
flutter test --no-pub test/module_kit_test.dart test/module_shared_rules_test.dart
flutter test --no-pub test/module_glance_test.dart test/ui_consistency_test.dart
flutter test --no-pub test/app_guide_test.dart test/version_test.dart test/whats_new_test.dart
```

- `flutter analyze` → `No issues found!`.
- `flutter test test/modules/assets` → 39 tests, all green. New tests cover
  the catalogue, future prices, stable order, percentages, freshness,
  mithqal and karat, the price/refresh/filter/unit flows, field errors and
  the compact Persian dark layout.
- The module gates, glance, UI consistency, guide, version, update and
  preview tests ran with the module in the same pass: 193 tests, all green.
  The full report is
  [`docs/35-assets-audit.md`](../../../../../docs/35-assets-audit.md).

The `review/` images were regenerated from the widget test's synthetic
holdings and prices; they are not real user data.

## Device checklist

1. After locally enabling a QA build on Android, open the cover and use the
   system screenshot and recents gestures before and after revealing. Repeat
   with a holding editor open. The general app lock should retain its own
   capture setting after the module closes.
2. In Persian, record a 750 gold weight and a different fineness, choose a
   Jalali purchase date near month end and add a named platform. Reopen an
   unfinished draft. Enter a grouped Persian amount and switch toman/rial.
3. Add a coin and a currency. Enter rates at different dates, verify missing
   coverage stays explicit, and test the two benchmark equivalents and the
   mithqal line.
4. Edit and delete a test rate, check fallback and Undo, then add a 10 g
   goal and check that changing rates does not move progress.
5. Open Prices, pick a coin or currency that is not held, record a price,
   and refresh an old price from the holdings prompt. Check both light and
   dark, Persian and English, and a large system font.

## Open questions

- Do users want their gold target to include documented coin content or
  prefer pure weight-only progress?
- For jewelry, would they benefit from noting invoice fees separately
  from an effective paid price per gram?
- Would a future transfer/sale history or named custody grouping be most
  useful after testing the private ledger?
