# Price Lens — `price_lens`

## What it does

A fully offline, voluntary calculator for two to four offers. Enter each offer's **total bundle price before discount**, its package quantity/unit, received count and optional paid count. Add one percentage or fixed discount and an explicitly allocated shipping/basket share. Cards show total payable and price per the selected common unit; results show all exact ties and extra cost relative to another entered offer, per unit and for the received quantity.

The live calculator is scratch state: it writes no offers or automatic drafts. Remembered prices and saved comparisons require explicit actions. Remembering an undated offer opens a shopping-date picker rather than inventing a historical date. Shopping dates are entered through the platform's shared date entry — typed civil `yyyy/MM/dd` or the calendar button beside it, Jalali where the app is set to it — and shown with the shared date label; storage stays ISO 8601. Saved comparisons restore the selected common unit, and replacing typed offers with a saved comparison is confirmed first. Reset keeps stored history and offers Undo while the calculator remains empty. Invalid stored history stays manageable with confirmation and raw Undo.

## Records

Only this module's `NexModuleStore` is used. New records have schema 2; known legacy schema 1 records remain readable.

| Kind | Body |
|---|---|
| `memory` | label, price (rounded minor-unit compatibility field), currency/currency_code/currency_exponent, quantity/quantityDen, unit, packageCount, ISO 8601 civil calendar date; new paid_num/paid_den decimal strings retain exact fractional minor units |
| `comparison` | ISO 8601 civil calendar date, two to four offer bodies, optional commonUnit |
| offer body | label, bounded integer price, explicit currency metadata, quantity/quantityDen, unit, received packageCount, optional paidCount, discount kind and exactly one matching value, optional shippingMinor and optional ISO 8601 civil date |
| `operation` | temporary module-local write journal with raw before/after records and commit marker; recovery and guarded Undo |

Example: a 2+1 promotion costs **2000 USD minor units in total before discount**, receives three 1 kg packages and pays for two. The price remains 2000; the received quantity is 3 kg. A 10% discount and 100 minor units of shipping produce 1900 total payable. Counts never multiply a total that was already entered.

Readers reject unknown/mismatched currency precision, invalid calendar dates, nonpositive/oversized quantities and denominators, invalid counts, negative shipping, stacked/unknown discounts and fixed discounts above the total. They preserve raw records for recovery/Undo. Invalid options in a saved comparison can be reopened for explicit repair and cannot produce a price ranking. Unknown currency or unit must be chosen explicitly during repair. Malformed history can be deleted and restored without losing unknown fields.

## Decisions

- Derived calculations use reduced `BigInt` rationals. Native integer overflow cannot reverse price ordering, corrupt unit conversion or manufacture a tie. Denominator signs are normalized and division by zero is refused. Persisted input integers stay bounded and JSON-safe; arbitrary-precision derived values are not forced into JSON integers.
- A bundle price is the total for all paid packages **before discount**. Received count multiplies quantity only; paid count describes the promotion and cannot exceed received count. Discount is applied once to the total, then shipping is added once. Zero price, zero discount and zero shipping are explicit valid amounts.
- Currency code and exponent are recorded together. Fourteen offered currency exponents were checked against [SIX's official ISO 4217 source](https://www.six-group.com/en/products-services/financial-information/market-reference-data/data-standards.html), published 2026-09-17. There is no FX conversion. IRR has exponent 2; one toman is ten rials. Toggling rial/toman re-expresses price, fixed discount and shipping together without changing their value.
- Compare only one currency and one unit family. Any mass/volume/piece mismatch blocks the entire ranking; no subset is labelled cheapest. Supported units are g/kg, international avoirdupois oz/lb, ml/L, explicitly **US** fl oz and whole pieces. Factors are exact rational definitions; international pound is 453.59237 g, ounce is pound/16, and US gallon is 231 cubic inches with the inch exactly 25.4 mm. See [NIST's unit conversion tables](https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b8) and [US gallon definition](https://www.nist.gov/how-do-you-measure-it/how-do-you-measure-fuel-gas-pump). No density or Imperial fluid-ounce conversion is guessed.
- Money is bounded to 10^15 minor units per price/shipping entry. Received/paid counts are positive integers up to 100,000. Quantities use at most 15 input digits and three decimals for mass/volume; pieces are whole. Persian/Arabic digits and decimal separators are accepted. Signs, exponents, grouping punctuation, excess precision and malformed denominators are refused.
- Price ranking and remembered paid amounts remain exact. Display alone truncates to currency exponent + 2 decimals; `≈` appears only when truncation actually loses precision. Exact terminating decimals have no approximation mark. Rounded compatibility fields do not replace exact memory values.
- History matching uses normalized label whitespace/case, the same currency, physically equal per-package quantity within a family, and the same received count. 750 g and 0.75 kg can match; different brands/labels are not inferred to be equivalent. Only strictly earlier calendar dates qualify, with deterministic latest-entry selection. The message identifies the offer and says it is your entered historical price, never a shop/market claim. Same-day and future entries do not support a price-change claim.
- Writes and their reloads are serialized. Failed reads show Retry; failed opt-in saves keep offers and stable retry IDs prevent duplication. Module-local journals recover failures after writes, and raw Undo refuses conflicting subsequent changes. Cross-process transactions are unavailable through the current API.
- Shopping dates use the platform's shared Jalali date entry (`NexModuleDateEntry`, `nexPickModuleDate`) and display (`nexModuleDateLabel`): typed civil `yyyy/MM/dd` (1900–2100, one separator style, never a future day) or the calendar button, following the app's calendar setting. The storage boundary stays ISO 8601 civil, so readers and backups never change.
- Nex tokens, panels, sheets, routes and dialogs; 48dp wrapping choices, readable total/per-unit labels, scrollable forms, Persian/English, RTL/LTR and both themes. No core, ARB, catalog, package or permission changes are required.

## Guide

**English.** Enter the price of the whole deal, not the price of one item multiplied a second time. Enter how much one package contains, how many you receive, and how many you pay for. Add one discount and shipping only if known. Add a second comparable offer and choose the common unit. The lowest exact unit price wins; an offer may have a higher total but a lower unit price. This says nothing about quality or product equivalence. Remember a price with its shopping date or save a comparison when you want it kept. Reset only clears the calculator.

**فارسی.** قیمت کل پیشنهاد را پیش از تخفیف وارد کنید؛ مبلغ هر بسته را دوباره در تعداد ضرب نکنید. مقدار داخل هر بسته، تعداد دریافتی و تعداد پرداخت‌شده را مشخص کنید. یک تخفیف و در صورت اطلاع سهم ارسال را اضافه کنید. پیشنهاد دومِ هم‌ارز و هم‌خانواده را وارد کنید تا قیمت واحد مقایسه شود. قیمت کل بالاتر لزوماً قیمت واحد بالاتر نیست؛ کیفیت کالا از این مقایسه نتیجه نمی‌شود. برای نگهداری، قیمت را با تاریخ خرید به خاطر بسپارید یا مقایسه را ذخیره کنید. «از نو» فقط ماشین‌حساب را پاک می‌کند.

## Changelog

**English.** Replaced overflowing integer fraction products with arbitrary-precision rational math; corrected sign/hash/display behavior, whole-ranking family checks, bundle validation and fixed-discount limits. Added explicit currency precision, Unicode input, fractional g/ml, exact remembered paid fractions, normalized same-spec matching and earlier-date requirements. Added raw guarded Undo, write recovery, serialized persistence, stable retries, incomplete-history management and read/save feedback. Improved payable/unit labels, rial/toman conversion of all money fields, wrapped controls and 320×480/2× layouts. Adopted the shared Jalali date entry/display for shopping dates, fixed Persian digits on multi-pack quantities and percentage discounts, an accurate N-way tie note, a toman-labelled price field, and a confirmation before a saved comparison replaces typed offers. The empty calculator now asks for its first offer in plain words, the currency row's chevron follows the reading direction, and the Persian date error reads naturally.

**فارسی.** حساب کسری در مقادیر بزرگ دقیق شد؛ تخفیف، تعداد بسته‌ها و ناسازگاری واحدها اصلاح شدند. دقت ارز، ورودی فارسی/عربی، گرم/میلی‌لیتر اعشاری، حافظهٔ مبلغ دقیق و تطبیق مشخصات و تاریخ قبلی اضافه شدند. بازیابی خطا، Undo دادهٔ خام، ذخیرهٔ مرتب، تکرار امن و مدیریت سوابق ناقص بهبود یافتند. جمع پرداختی، واحد مقایسه، تبدیل ریال/تومان و فرم کوچک روشن‌تر شدند. ورود و نمایش تاریخ خرید با تقویم مشترک شمسی انجام می‌شود؛ رقم‌های فارسی روی مقدار و تخفیف، اعلام دقیق تساوی چند پیشنهاد، برچسب تومان کنار قیمت و تأیید پیش از جایگزینی پیشنهادها اضافه شدند. پیام ماشین‌حساب خالی و خطای تاریخ فارسی طبیعی‌تر شدند و فلش سطر ارز در جهت خواندن می‌چرخد.

## Platform requests

Store transactions with cross-process conflict detection would improve future versions; until then the module keeps its own serialized write journal with recovery and guarded Undo. Barcode/OCR, retailer prices, notifications and network access remain outside scope. Shared Jalali date entry/display — previously requested — is now provided by the platform and used for every shopping date. No new runtime dependency is needed.

## Checks

Validated against Nex main `724b999a91c5b7366fbb4d9e8f17b36a3fb16318`, Flutter 3.35.5 / Dart 3.9.2, and re-validated in-tree after the shared-date-entry pass. Original test cases were retained in same-library parts; expectations changed only for deliberate corrections such as exact decimal labels, valid free offers, refusal of partial family rankings, the replace-offers confirmation and the empty-state wording.

`dart format lib/modules/price_lens test/modules/price_lens` is clean and `flutter analyze --fatal-infos` reports no issues. `flutter test test/module_kit_test.dart -j 2`: **40 passed**; `flutter test test/modules/price_lens -j 2`: **95 passed**. Tests cover large rational products, unit factors, ties (including the counted tie note), bundles, one discount, Unicode/currency bounds, malformed records, exact historical fractions/dates/specs (750 g ↔ 0.75 kg), typed and picked shopping dates with future-day refusal, a stored offer with a broken date repaired through the editor, recovery after committed writes, raw conflicting Undo, failed opt-in save/retry, the replace-offers guard, Persian-digit rendering, and all four locale/theme combinations for the offer editor at 320×480 and 2× text. Final full-client/package results, capture evidence and remaining real-device checks are in [the phase-four validation report](../../../../review/VALIDATION.md).

## 2.1.11 changes

- 2.1.11: Copy result (plain lines); one primary action on an empty page.
- 2.1.12: a one-sentence result with the percentage saved; per 100 g and 100 ml units.
