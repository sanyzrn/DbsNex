# Price Lens — ذره‌بین قیمت (`price_lens`)

## Audit — upgrade from main `e3edff3fc5e41ad1c556ab8b96a302940fa83b16`

Branch: `agent/module-price_lens`. **Rollout remains Soon.** The brief, task,
then brief were read before coding; the existing source/tests and platform
references were reviewed first. Baseline module + kit: **147 passed**
(95 module tests, 52 kit tests).

| Screen / area | Before this upgrade | Result |
|---|---|---|
| Calculator | Exact BigInt fractions, 2–4 offers, bundles, discounts, shipping, ties, 14 currencies | **Done:** retained; localized money, shared choices, privacy and system sharing added |
| Units | Weight, volume and pieces; no roll/sheet distinction | **Done:** rolls, sheets and 100-sheet quantities; no invented roll-to-sheet equivalence |
| Price memory | Flat dated history; exact same-pack lookup only | **Done:** product histories, explicit shop/product fields, search and normalized changes across pack sizes; original flat list retained in More actions |
| Shopping | No saved-product list | **Done:** persistent bought/needed checklist, latest known prices and estimates separated by currency |
| Product history | No product detail page | **Done:** latest price, exact unit price, percentage/time change, changed-package explanation, dated shop history, new observation, delete/Undo and text sharing |
| Saved comparisons | Save/open/delete/Undo already worked | **Done:** retained, including confirmation before replacing current offers and common-unit restoration |
| Leaving | Calculator lost on exit; editor offered discard | **Done:** platform drafts preserve calculator, selected tab/unit and unfinished editor; failed reads block replacement and show Retry |
| Money | IRR used 100 internal minor units per rial | **Done with compatibility boundary:** new whole Iranian amounts use named Rial fields; legacy integers and exact derived fractions retain their meaning |
| Compatibility | Raw Undo worked; serializers dropped unknown fields | **Done:** unknown business-record fields and nested person metadata survive serialization; writes reread raw records; future versions cannot be overwritten |
| Look / access | Custom pills, all fields at once, one file over 400 lines | **Done:** shared adaptive choices, optional details, retained tab state, money masking, files below 400 lines; FA/EN × light/dark × 320×480 at 2× checked |
| Shared projections | No record summary; purchase dates are historical | **Done locally:** pure private summaries and empty due projection. **Integration pending:** protected shared test still lists this module in `summaryPending`; see Platform requests |

## Maintainer review (2.8.4)

Reviewed after merge and made available; the protected shared-rules test no
longer lists `price_lens` as pending a `summarize`. Persian fixes seen on
the review screens:

- A unit price was forced left to right, so it read «ریال / کیلوگرم ۱۲۰٬۰۰۰»;
  it follows the page now: «۱۲۰٬۰۰۰ ریال / کیلوگرم».
- Decimals use «٫» (`persianLocal`, the money formatter, pack quantities):
  «از ۱ کیلوگرم به ۰٫۷۵ کیلوگرم», not «0.75».
- Facts on one line are joined with «،» in Persian (`lensSep`): a middle dot
  beside a number reads as the Persian zero, so «۱ · کیلوگرم» looked like «۱۰».

## What it does

A fully offline shelf companion: compare actual offers, remember your own
prices, spot a smaller pack at the same price, and reuse those products as a
shopping list. Nothing is scraped or sent to an AI service.

- **Compare:** enter an offer name, total price, package quantity and unit.
  Optional details contain the common product name, shop, received/paid
  package counts, one discount, allocated shipping and shopping date. All
  exact ties and extra costs are shown. Copy and system Share both work.
- **My products:** search explicitly named products, see their latest
  recorded price and unit-price change. Names normalize whitespace/case and
  Persian/Arabic ی/ک; brands and product equivalence are never inferred.
- **Product detail:** chronological price observations, shop and shopping
  date, price per kg/L/piece/roll/sheet, percentage change and elapsed civil
  days. A 1 kg pack becoming 750 g at the same total price exposes **+33.3%**
  per kg. Record a new price without reusing the previous shop or price.
- **Shopping list:** all saved products, bought/needed checkboxes and a
  needed-only filter. Estimate = one last-recorded bundle of each needed
  product; each currency has its own total. This is not a live quotation.
- **More actions:** original flat Price memory and Saved comparisons remain
  available; malformed records can still be deleted and exactly undone.

## Records

Only the module-bound `NexModuleStore` is used. There is no migration that
rewrites existing rows. Business schema 1/2 remains readable; schema 3 adds
explicit price/product/person fields. Unknown fields are retained. Unsupported
future versions remain visible as incomplete history and cannot be overwritten.

| Kind | Version / body |
|---|---|
| `memory` | `schema: 3`; `label: String`, optional `productName: String`, `person: Map`; money below; `quantity: int`, optional `quantityDen: int`, `unit: String`, `packageCount: int`, `date: ISO String`; optional `recordedAt: ISO timestamp`, `paid_num` / `paid_den`: exact decimal integer strings |
| `comparison` | `schema: 3`, `date: ISO String`, optional `commonUnit: String`, `options: List<Map>` of the full offers |
| offer inside comparison/draft | `label`, optional `productName`, `person`; money below; quantity numerator/denominator, unit, received count, optional paid count, `discount: none/percent/fixed`, optional `discountPercent`, optional shopping date |
| `shopping` | `v: 1`, `productKey: String`, `bought: bool`; key = currency + measurement family + normalized explicit product name |
| `draft` | Platform `NexModuleFormDraft` v1 envelope (`base`, `fields`); `workspace` keeps offers, unit, tab and `workspaceVersion: 1`; `offer:new` / offer-id / price-entry identity keeps controllers and stable retry ID. Not saved history or summary data |
| `operation` | Internal journal v1, `before: List<{kind,id,body}>`, optional `committed: bool`; validated in full before recovery. Only memory/comparison/shopping/draft targets may be replayed; invalid journals are quarantined |

**Money boundary.** New whole Iranian amounts use `priceRial`,
`discountRial`, `shippingRial`: integer **rials**, never tomans. Foreign base
prices use `amount` in the currency's smallest unit plus `currency`; existing
foreign discount/shipping minor-unit fields retain their meaning. Existing
`currency_code` / `currency_exponent` metadata describes the legacy exact
calculator scale. In particular, **legacy IRR `price: 100` means 1 rial**;
it must never be reinterpreted as 100 rials. `storage_money.dart` is the only
adapter between canonical Rial fields and that internal scale.

Legacy aliases are retained when the original record had them and checked
for agreement. Old sub-rial quotations and non-integral discounted totals
retain their legacy compatibility field plus authoritative exact fraction;
they are never rounded into a fabricated `priceRial`. The editor has a small
compatibility boundary for unchanged legacy sub-rial values. New ordinary
price entry uses the shared whole-rial amount field. Arithmetic and ranking
remain arbitrary-precision rational; approximation is presentation only.

A shop is stored as `person: {name: ...}`. Unknown `id`, `cards`, `ibans` and
other person metadata are preserved, never requested or included in sharing.
The original store order/timestamp resolves same-shopping-day entries; the
shopping day determines which date is latest, not the last edit of an older
purchase. Future shopping dates remain in history but do not enter estimates.

## Decisions

- Keep the existing exact calculator, currencies, discounts, opt-in saves,
  recovery journal and raw guarded Undo. Upgrade them; do not replace them.
- Product grouping uses an explicit common product name, falling back to the
  original offer label. Changing pack size is comparable within a measurement
  family; changing currency or mass/volume/count kind creates another group.
- Rolls, sheets and generic pieces are distinct. There is no fixed number of
  sheets in a roll, no density guess, and no assumption of equal quality.
- Trends compare the latest known observation with the latest **strictly
  earlier shopping day**, normalized to a consistent unit. A free baseline
  or same-day-only history produces no percentage claim. The timeline still
  shows the underlying prices. Elapsed time is days, never days divided by
  30 and called Persian months.
- New price observations prefill product/quantity/unit only. Price and shop
  start empty; date is visibly today and editable. Stable IDs make save retries
  idempotent; failed draft cleanup retries cleanup without another save.
- Stateful tabs use `IndexedStack`: calculator offers, searches and scroll
  positions survive switching. Discount input swaps use `NexSegmentSwap`.
  Optional details use the shared closed affordance and direct open fields:
  this avoids a zero-duration `AnimatedSize` layout mutation at 2× reduced
  motion. Every FAB has `heroTag: null`.
- No reminder is invented for a historical purchase. No private calendar,
  notifications, exchange rates, shops, network clients or new dependencies.
- The first version deliberately keeps the calculator's explicit rial entry
  default; switching to toman re-expresses all three money fields without
  changing value. Both displays use the shared money formatting. A common
  app-wide preferred unit remains a platform decision.

### Shared rules — all nine

| Rule | Implementation |
|---|---|
| 1. Due shape / calendar | Exact `ModuleDue` shape and pure `duesBetween(from,to) => []`; historical prices are not dues. FA display and picker explicitly Jalali through platform APIs, ISO storage unchanged |
| 2. Money | Named whole-Rial fields for new integral Iranian amounts; foreign smallest units; explicit legacy adapter, no reinterpretation or silent rounding |
| 3. Person | Shop in `person.name`; nested unknown identity/banking metadata retained and excluded from sharing |
| 4. Summary | Pure `summarize(ModuleRecord)` → `{title, detail, private}`; memory/comparison summaries private; drafts, journals, shopping state and malformed/other-module records return null; no search/AI hookup |
| 5. Unknown fields | Business serializers retain unknowns; controller merges fresh raw metadata; unsupported versions are protected; raw Undo restores the exact body |
| 6. Saving / Undo | Platform form drafts + copied reference guard; serial writes, durable recovery, stable retry IDs, guarded Undo in Nex banners |
| 7. Reminders | Not applicable: no future event/reminder is created for price history; no custom scheduler |
| 8. Sharing / privacy | `nexModuleShareText` for comparisons/history; hide control redacts amounts and percentage claims in UI, copy and share; only product/date/quantity/user-entered shop exported |
| 9. Shared look | Nex hero/panel/search/segments/motion/dialog/sheet/route/banner; adaptive layouts, directional text, optional details, retained tabs, null FAB heroes; both languages/themes and 2× checks |

Copied references, with the **same filenames and calls**: `money_format.dart`,
`amount_field.dart`, `currency_field.dart` from `lent_borrowed`, plus their local
money/number/unit helper dependencies; `draft_guard.dart` and `form_draft.dart`
from the same reference. Imports/string binding are module-local. The existing
14-currency picker is retained so the public precision catalog does not silently
expand; the reference currency field is included for the future common picker.
`legacy_amount_entry.dart` only prevents the shared whole-rial formatter from
truncating old sub-rial records; ordinary inputs still use `AmountField`.

### Research

Presentation follows primary-source unit-pricing guidance: compare a consistent
quantity, account for package size, and do not assume a bigger pack is cheaper.
These are design inferences, **not Iranian market-price data**. All displayed
prices and shops are user input; screenshot values are test fixtures.

- [NIST Unit Pricing Guide, 2025](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/1181e2025/NIST.SP.1181e2025.html)
- [CMA consumer unit-pricing guidance](https://www.gov.uk/government/publications/unit-pricing-information-for-consumers/unit-pricing-information-for-consumers)
- [NIST conversion tables](https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b8): retained exact mass/volume definitions; US fluid ounces are explicitly labelled US

## Guide

**English.** Compare two offers using their whole-deal price and the quantity in
one package. Add received counts, one discount and shipping only when known;
counts do not multiply the entered price again. Give the same product a common
name in More details, and remember prices with their shopping date and shop.
My products shows changes per unit, even when pack size changes. Use Shopping
list to tick bought items; its estimate uses your recorded prices. The eye
button hides financial amounts, including in copied/shared text. Leaving keeps
unfinished work; reset clears the calculator while saved history stays.

**فارسی.** قیمت کل پیشنهاد و مقدار داخل هر بسته را وارد کنید و پیشنهاد دوم را
اضافه کنید. تعداد دریافتی، یک تخفیف و سهم ارسال را فقط در صورت اطلاع بنویسید؛
تعداد بسته دوباره در قیمت ضرب نمی‌شود. در جزئیات بیشتر برای بسته‌های یک کالا
نام مشترک بگذارید و قیمت‌ها را با تاریخ خرید و فروشگاه ذخیره کنید. «کالاهای من»
تغییر قیمت واحد را حتی با کوچک‌شدن بسته نشان می‌دهد. در فهرست خرید کالاهای
خریده‌شده را تیک بزنید؛ برآورد بر اساس قیمت‌های ثبت‌شدهٔ خودتان است. دکمهٔ چشم
مبلغ‌ها را در صفحه و متن اشتراک‌گذاری پنهان می‌کند. کار نیمه‌تمام با خروج حفظ
می‌شود و پاک‌کردن مقایسه، تاریخچهٔ ذخیره‌شده را حذف نمی‌کند.

## Changelog

**English.** Added product histories with unit-price/pack-size changes, shops,
reusable shopping lists, text sharing, money privacy, retained workspace/editor
drafts, rolls/sheets and canonical Rial storage while preserving legacy data.

**فارسی.** تاریخچهٔ کالا با تغییر قیمت واحد و اندازهٔ بسته، فروشگاه، فهرست خرید
ماندگار، اشتراک‌گذاری متن، پنهان‌کردن مبلغ، حفظ کار نیمه‌تمام، رول و برگ و
ذخیرهٔ ریالی با حفظ معنی داده‌های قبلی اضافه شد.

## Platform requests

1. **Required integration, outside this task's allowed folders:** remove only
   `'price_lens'` from `summaryPending` in
   `apps/client/test/module_shared_rules_test.dart`. The new pure projection
   meets the rule, but that test currently *requires pending modules not to
   have it*. Prompt 12 explicitly forbids changing the gate/shared files, so
   this branch leaves that file untouched. Do not hide the function from its
   regex or relax the test. This is a known CI blocker until maintainers
   graduate this one entry.
2. Future platform-owned summary/search/AI integration with explicit privacy
   consent. Today the projection is pure and local; nothing is indexed or sent.
3. Store transactions/conflict detection across processes. Today a local serial
   journal, recovery and guarded Undo protect writes; no cross-process sync is
   claimed.
4. Optional future app-wide rial/toman preference, image sharing and barcode/OCR
   input. Today money uses the reference formatter and explicit unit switch,
   sharing is text, and prices are entered by the person. None blocks normal
   module use. No external price source is requested.

## Checks

Toolchain: repository-pinned **Flutter 3.47.9 / Dart 3.13.7** (the prompt's
3.35.x is older than the current repository). `flutter pub get --enforce-lockfile`
succeeded without dependency/lockfile changes. Runtime and logs live outside
the repository.

```text
flutter analyze --no-pub --fatal-infos
No issues found! (ran in 7.9s)

dart format --output=none --set-exit-if-changed lib/modules/price_lens test/modules/price_lens
Formatted 67 files (0 changed) in 0.41 seconds.

flutter test --no-pub test/module_kit_test.dart test/modules/price_lens --concurrency=2 --reporter expanded
01:14 +177: All tests passed!

# Final regression pass after draft common-unit/menu guards and shared discount swap:
flutter test --no-pub test/modules/price_lens/products_widget_test.dart test/modules/price_lens/reliability_widget_test.dart --concurrency=2 --reporter expanded
00:17 +17: All tests passed!

flutter test --no-pub test/modules/price_lens/screen_review_test.dart --dart-define=NEX_CAPTURE=lib/modules/price_lens/review --concurrency=1 --reporter expanded
00:13 +8: All tests passed!
```

The final module has **126 tests**; the kit has 52. Original arithmetic,
comparison, compatibility, repair and Undo coverage was retained. New checks
cover shrinkflation, date ordering/timestamps, zero baselines, large percentages,
unit families, legacy/canonical money, unknown person metadata, future versions,
malicious recovery targets, shopping failure/retry/concurrency, draft restoration
and read failure, Jalali display and masking/system sharing.

**Full client run, completed once:**

```text
flutter test --no-pub --concurrency=2 --reporter expanded
23:55 +4173 ~4 -2: Some tests failed.

Failing tests:
  test/module_shared_rules_test.dart: module "price_lens" has a line about each record
  test/modules/reviewed_three_test.dart: price lens copies its result as lines
```

The first failure is the protected `summaryPending` graduation described above;
it remains unresolved in this branch because editing that shared file is
explicitly outside the task scope. No test was skipped to conceal it.

The second exposed a real compatibility issue: the new shared formatter added
a quality-note footer to **Copy**, changing its original four-line shape. Fixed
inside `lens_result_panel.dart`: Copy keeps its original header/headline/offer
lines, and the extra note belongs only to system Share. The unchanged shared
integration test and all new product/draft/privacy widget tests then passed:

```text
flutter test --no-pub test/modules/reviewed_three_test.dart test/modules/price_lens/products_widget_test.dart --concurrency=2 --reporter expanded
00:19 +20: All tests passed!
```

Analysis and formatting were rerun clean after that fix. **The remaining known
CI blocker is only the protected shared-test pending-list entry.** The complete
client run is not described as green. Four existing tests were skipped by the
suite's normal configuration, not by this module.

Screenshots below are real rendered module screens using seeded test data;
FA dark and EN light at 390×844. All four locale/theme combinations also traverse
compare → products → history → shopping at 320×480 with 2× text and reduced
motion. No physical Android share sheet or keyboard was tested in this runtime.

| Screen | Persian dark | English light |
|---|---|---|
| Compare | [image](review/price_lens_fa_dark_compare.png) | [image](review/price_lens_en_light_compare.png) |
| Result | [image](review/price_lens_fa_dark_result.png) | [image](review/price_lens_en_light_result.png) |
| Products | [image](review/price_lens_fa_dark_products.png) | [image](review/price_lens_en_light_products.png) |
| History | [image](review/price_lens_fa_dark_history.png) | [image](review/price_lens_en_light_history.png) |
| Shopping | [image](review/price_lens_fa_dark_shopping.png) | [image](review/price_lens_en_light_shopping.png) |

## Device checklist

1. With the module enabled locally for QA, compare two differently sized packs;
   try a tie, 2+1 bundle, discount, shipping and a mixed-family/currency refusal.
2. Type Persian/Arabic numbers, switch rial/toman, check all monetary fields and
   amount words; reopen an old comparison and ensure its value is unchanged.
3. Enter/pick a Persian shopping date, including Esfand/month/year boundaries;
   ensure every visible date stays Jalali and future dates are refused.
4. Leave an unfinished offer, revisit it, switch tabs, close/reopen the module;
   confirm offers, unit, tab and typed work survive. Reset and Undo.
5. Save two dated prices under one product name, change package size, verify the
   normalized trend and shop; add another observation and verify price/shop are
   empty rather than copied from the last receipt.
6. Tick shopping items, filter needed, reopen; verify totals per currency and
   that a product without an eligible date does not enter the estimate.
7. Hide money; open history, Copy/Share a comparison and Share product history;
   inspect the **real phone share sheet** and ensure no amounts/percentages or
   person banking metadata leak. Delete/Undo a price and a saved comparison.
8. Check small screen, large system fonts, dark/light, RTL, keyboard insets,
   swipe-back and widget-launch return. Enable rollout only after device QA.

## Open questions

- Should shopping checkmarks reset on a new price or only when explicitly
  unticked? This version keeps the user's choice across visits and new prices.
- Should a later version add desired quantities/categories or independent
  shopping lists? This brief's list uses one last-recorded bundle per product.
- Should all Nex money modules share a preferred toman/rial display setting?
  This version preserves the existing calculator entry default and offers both.
- Real shoppers must choose whether product naming needs suggestions/barcode
  assistance. This version never infers that two brands or shops are the same.
