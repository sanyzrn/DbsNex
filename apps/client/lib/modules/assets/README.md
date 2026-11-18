# Asset book · دفتر دارایی

## What it does

An offline ledger for gold by weight, Iranian coins, foreign currency and
named assets. This is a new module from main commit
`004306c13d1878206271d522f882257a417e693f`, so there is no prior module to
audit. The branch contains the module's source, tests and review images.
The module awaits platform registration and rollout review.

- **Covered book.** On Android, the book acquires `NexSecureWindow` before
  any data can be revealed. A failed acquisition leaves the book covered.
  Opening the screen, going to the background, and tapping the eye return
  it to a cover with no names, places, amounts or counts. This also covers
  an open editor and retains its input.
- **Holdings.** A separate row for each purchase records quantity, purchase
  date, paid unit price and custody. Home, bank box, named platform and
  other labels help locate the entry without displaying those details on
  the dashboard. Each valued lot shows its dated quote and estimated gain
  or loss. A missing rate leads directly to that asset in Prices.
- **Prices.** Manually enter today's or an earlier price and keep all
  observations. See the latest value and date, then the older entries for
  the selected asset. 18k gold and USD are always available as benchmarks.
  Emami, Bahar Azadi, half, quarter, gram and custom coins have distinct
  histories. Names of platforms are labels with no links.
- **Value in gold and dollars.** The same priced subtotal is shown in rials
  or tomans, in 18k grams and in USD. The two conversions display their
  benchmark dates. Coverage shows how many holdings have an eligible
  rate. With partial coverage the heading says “Value of priced holdings.”
- **Goals.** Set any number of named gold targets. Progress comes from net
  weight and fineness. The amount remaining stays meaningful even while
  prices are missing.

## Records

All data is stored with `NexModuleStore` in the module's own local storage.

| Kind | Version and fields |
| --- | --- |
| `holding` | `v: 1`, `type/code/name: String` (identity below), `bought: ISO local civil-day timestamp`, `costPerUnitRial: int`, `fineness: int` (parts per thousand, 750 for non-gold), `custody: home/bank/platform/other`, `location: String`. Physical gold stores `quantity: int` in mg. Coins and named other assets store whole units. Foreign holdings store `amount: int` in ISO minor units and `currency: String`. |
| `quote` | `v: 1`, `type/code/name`, `date: ISO local civil-day timestamp`, `unitRial: int`. Gold price per 18k gram. Coin, foreign currency and other prices per full unit. |
| `goal` | `v: 1`, `title: String`, `targetMg: int` in milligrams of 18k-equivalent physical gold. |
| `draft` | Shared form-draft envelope and original-body fingerprint. Includes text fields, kind selections, local civil day, unit and stable record ID for retry. No financial projections read draft rows. |

Holding and quote identity is the same asset family and variant. Standard
coins have dedicated codes. Foreign currencies use the copied offline ISO
minor-unit table and quote prices in rials per one major unit. For custom
assets, the entered name identifies the price series after normalizing
spaces, case and Persian/Arabic kaf and yeh. A custom coin and another
asset of the same name remain separate. Renaming a custom holding can
point it at a different quote history. Editing preserves fields the module
does not own and fails on a conflicting stored body. Unreadable and
future-version rows are preserved with a warning.

## Decisions

- **Prices in familiar units.** The [TGJU market board](https://www.tgju.org/tv/)
  separates Iranian coin types and quotes 750 gold per gram. The
  [TGJU coin reference](https://www.tgju.org/coin) describes the Emami and
  old-design distinction. These sources informed labels and units. The
  module contains no sample market rates or network logic.
- **One comparable metal rate.** 18k rate × net grams × fineness / 750.
  The price paid per actual gram can include costs the owner chose to
  include. This estimates metal value without making charges, fees, stones
  or coin premiums inferred from weight. Coins use their own typed rates.
- **Exact money.** Paid price and quotes are whole rials. Toman is the
  default presentation and entry unit. BigInt intermediates keep products
  and sums exact. Each lot rounds half up to the nearest rial for both cost
  and value; the dashboard sums those same displayed lot values. Equivalent
  results round to milligrams and USD cents for display.
- **Incomplete coverage.** Quotes from the future and quotes earlier than
  the purchase do not value a lot. The latest date wins; same-day
  corrections use storage update time, then ID to break ties. An unpriced
  lot is excluded from both the estimate and its matching cost total.
  Benchmark prices carry their own dates. The gold target is based only
  on held metal normalized to 18k; coins and price movements do not count.
- **Privacy scope.** `NexSecureWindow` controls Android window capture on
  entry through exit, including editor sheets. The cover hides names,
  amounts, numbers and storage labels while the app is inactive. The book
  uses the normal Nex storage and backup policy. Confirm capture and
  recents behavior on a physical Android phone before rollout.
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
| Shared look | Nex hero, panels, typography, adaptive segments and transition, shared sheet, date picker, dialogs and overlay. |

## Guide

**English.** Reveal the book and add the first holding using the date and
paid price per unit. Enter the latest price you have for that asset under
Prices. For your benchmark comparison, add the 18k gram and USD rates.
Use the dated prices to interpret the estimate and its coverage. Set a
gold weight target under Goals. The eye covers the book at any time.

**فارسی.** دفتر را باز کن و اولین دارایی را با تاریخ و قیمت خرید هر واحد ثبت
کن. در «قیمت‌ها» آخرین قیمتی را که داری با تاریخ وارد کن. برای دیدن معادل
ارزش سبد، نرخ هر گرم طلای ۱۸ عیار و هر دلار را هم ثبت کن. عدد پوشش نرخ
نشان می‌دهد چند ثبت در برآورد حساب شده‌اند. در «هدف‌ها» وزن طلای دلخواهت را
بگذار و با دکمهٔ چشم هر وقت خواستی دفتر را بپوشان.

## Changelog

**English.** Added the private Asset book with dated valuations, gold and
USD comparisons and physical gold goals.

**فارسی.** دفتر خصوصی دارایی با قیمت‌های تاریخ‌دار، معادل طلا و دلار و پیشرفت
هدف طلای وزنی اضافه شد.

## Platform requests

- Register `AssetsModule()` in `nexModules`, reserve the module hue and
  place the catalog entry in Soon for integration review. Per task 12, the
  temporary local registry entry is excluded from this branch. The registry
  assertion needs that integration. The catalog inventory tests should
  account for the added module in the integration branch.
- Live quotes would require a platform-owned, opt-in source, user-approved
  units and timestamps, and explicit labeling. The module is complete with
  manual prices; future integration must preserve manual history and the
  distinction between entered and retrieved prices.

## Checks

- Dependencies resolved with `flutter pub get --enforce-lockfile` using the
  repo toolchain.
- `flutter analyze --no-pub --fatal-infos` → `No issues found!`.
- `flutter test --no-pub test/module_kit_test.dart test/module_shared_rules_test.dart test/ui_consistency_test.dart test/modules/assets --dart-define=NEX_CAPTURE=lib/modules/assets/review --reporter expanded`
  with local registration → `00:08 +139: All tests passed!`.
- The whole client run with local registration
  (`flutter test --no-pub --concurrency=6 --reporter expanded`) ended at
  `05:53 +4438 ~5 -6`. Four large-text asset tests asserted a row before
  scrolling it into view. Two catalog tests encoded the original count of
  16 add-ons and saw 17 because of the temporary local registry line.
- After correcting the scroll assertion, the module, kit, shared rules and
  UI consistency recheck without the screenshot flag reported
  `00:12 +140: All tests passed!`. After removing the temporary registry
  line, `flutter test --no-pub test/module_preview_test.dart --reporter expanded`
  reported `00:01 +7: All tests passed!`. The post-fix validation was focused.
- Tested Persian/English, light/dark, 320 px with 2× text and reduced motion.
  Screenshots below show fabricated test holdings and test prices.

| Screen | Persian dark | English light |
| --- | --- | --- |
| Cover | [Image](review/fa_dark_private.png) | [Image](review/en_light_private.png) |
| Holdings | [Image](review/fa_dark_holdings.png) | [Image](review/en_light_holdings.png) |
| Price history | [Image](review/fa_dark_prices.png) | [Image](review/en_light_prices.png) |
| Gold goals | [Image](review/fa_dark_goals.png) | [Image](review/en_light_goals.png) |

## Device checklist

1. After locally enabling a QA build on Android, open the cover and use the
   system screenshot and recents gestures before and after revealing. Repeat
   with a holding editor open. The general app lock should retain its own
   capture setting after the module closes.
2. In Persian, record a 750 gold weight and a different fineness, choose a
   Jalali purchase date near month end and add a named platform. Reopen an
   unfinished draft. Enter a grouped Persian amount and switch toman/rial.
3. Add a coin and a currency. Enter rates at different dates, verify missing
   coverage stays explicit, and test the two benchmark equivalents.
4. Edit and delete a test rate, check fallback and Undo, then add a 10 g
   goal and check that changing rates does not move progress.

## Open questions

- Do users want their gold target to include documented coin content or
  prefer pure weight-only progress?
- For jewelry, would they benefit from noting invoice fees separately
  from an effective paid price per gram?
- Would a future transfer/sale history or named custody grouping be most
  useful after testing the private ledger?
