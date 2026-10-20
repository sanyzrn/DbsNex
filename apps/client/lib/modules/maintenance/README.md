# Maintenance — `maintenance`

## What it does

An offline service log for owned equipment. Home groups assets by due now, coming up within 30 days, scheduled, needs information, no schedule and archived. Each asset has its own service history, intervals, entered costs and current meter panel. Opening, changes and app resume recalculate standings. Nothing runs in the background on its own; the one reminder is an optional one-time device alert set on an asset, and it needs the module rolled out. Live sensors and manufacturer recommendations stay out.

Asset, service and interval editors retain raw local drafts. Current meter updates are separate records: they do not invent a service or reset its interval. Repeating a service copies the task and optional cost/provider/notes, and asks for a fresh meter reading. Archive preserves history; destructive actions ask once and offer guarded Undo.

## Records

Every record belongs to the module's own `NexModuleStore`. No sibling or core implementation imports.

| Kind | Body and version |
|---|---|
| `asset` | schema 2; nickname, type, optional model/purchasedAt/notes, meterKind (`none`, `distance`, `hours`), distanceUnit (`km`, `mi`), archived |
| `event` | schema 2; assetId, task, calendar date; optional cost + currency/currency_code/currency_exponent, meter + meter_scale + meter_kind + meterUnit, provider, notes |
| `rule` | schema 2; assetId, task; days **or** months; meters + meterUnit **or** hours; meter_scale |
| `reading` | schema 1; assetId, integer value, scale, meterKind, optional unit, UTC at, corrected |
| `draft` | raw strings and choices, parentId, stable target id, baseline fingerprint; never a service or total |
| `operation` | module-local temporary write journal; before/after bodies and commit marker for recovery |

Legacy whole readings have scale 1. New fractional inputs use scale 1000: `123.456 km` is `{meter:123456,meter_scale:1000}`. Known legacy currencies use their documented exponent. New costs store explicit ISO metadata. Unknown currency, inconsistent exponent, invalid day and incompatible counters are incomplete rather than silently reinterpreted. Invalid intervals remain visible for deletion with Undo. Raw unknown fields survive fresh edits and deletion/Undo, including malformed dependent records and drafts.

## Decisions

- Time and usage are independent triggers; either known trigger may make a service due. Time uses the latest nonfuture service for that task, otherwise the explicit purchase date. Month addition clamps to the destination month's last day; civil day arithmetic does not divide elapsed hours by 24. Dates preserve their written calendar day and refuse normalized invalid dates.
- Usage requires a real service reading for the task. No baseline is invented as zero. Latest entered service/manual reading supplies current usage. A correction below the service baseline needs information; it does not rewrite history. Future records do not become current.
- Distance conversion is explicit: `1 mi = 1.609344 km`, exact rational calculation with rounding to 0.001 of the destination unit. Original units remain on every record. Asset-unit selection does no conversion until Save; Keep original retains historical units. Conversion and preference/draft changes share a recovery journal. Hours never become distance.
- Meter inputs allow three decimals, Persian/Arabic digits and decimal separators, up to 1,000,000,000 units. Rules allow up to 365,250 days or 12,000 months, with resulting years limited to 1–9999. Invalid rules are refused rather than partially repaired.
- Optional service cost can be explicitly zero, or omitted as unknown. Typed cost needs a chosen currency. Money is bounded to 10^15 minor units per entry; totals use `BigInt` and stay separated by currency. There are no exchange rates. IRR uses exponent 2; one toman equals 10 rials, with exact re-expression when toggling the input mode. Fourteen offered currency exponents were checked against [SIX's official ISO 4217 source](https://www.six-group.com/en/products-services/financial-information/market-reference-data/data-standards.html), published 2026-09-17.
- Mutations and reloads are queued; same-task interval identity is resolved against fresh records. Failed reads show Retry, failed saves keep input. Local recovery journals and guarded raw Undo prevent partial grouped operations and refuse overwriting conflicting later changes. The public store API does not expose a database transaction or cross-process locking; simultaneous independent external writers remain a platform limitation.
- Nex tokens, panels, sheets, routes and dialogs; Persian/English, RTL/LTR, light/dark; wrapping 48dp choices and scrollable forms. Dates go through the shared module date entry and label: both typed-date pickers are solar-capable, every absolute date a person reads follows their saved calendar (Jalali with Persian digits for a solar reader, civil otherwise), and storage stays ISO 8601. No package, platform API, catalog, ARB or core changes are required.

## Guide

**English.** Add an asset and choose what it counts. Log actual work with its date and optional reading/cost. Add your own interval for each task. Update the current reading as equipment is used; this leaves the last service unchanged. A date or meter baseline that is missing is shown as needing information. Changing km/mi offers keeping original records or converting when saved. Closing edited forms can keep a draft or discard it. Costs are the figures you entered, grouped by currency. An optional device reminder for the next service can be set on an asset's own page.

**فارسی.** دستگاه را اضافه کنید و مشخص کنید با تاریخ، کیلومتر/مایل یا ساعت کار سنجیده می‌شود. سرویس واقعی را با تاریخ و در صورت نیاز کارکرد و هزینه ثبت کنید و فاصلهٔ دلخواه هر کار را تعیین کنید. «بروزرسانی کارکرد» سرویس جدید نمی‌سازد. مبنای نامعلوم یا کارکرد پایین‌تر از مبنای سرویس نیازمند اطلاعات است. تغییر واحد هنگام ذخیره می‌تواند تاریخچه را تبدیل کند یا واحدهای اصلی را نگه دارد. هنگام بستن فرم، پیش‌نویس را نگه دارید یا کنار بگذارید. هزینه‌ها فقط از داده‌های خودتان و جدا برای هر ارز جمع می‌شوند. برای سرویس بعدی می‌توانید روی صفحهٔ هر دستگاه یادآور گوشی بگذارید.

## Changelog

**English.** Added independent fractional current-meter records/history and correction confirmation; corrected dual-trigger due calculations, missing baselines, future filtering, calendar bounds and conversion. Added explicit currency metadata, Unicode parsing and exact large totals; fresh edits, serialized rules, raw compound Undo, recovery journals and draft/error handling. Improved small-screen forms, accessible controls, date/currency labels and incomplete-data states. This pass: shared Jalali-capable date pickers and calendar labels everywhere an absolute date is read, the shared multiline note editor for asset and service notes, an optional per-asset device reminder with its own notice that cancels with the record, archive feedback with Undo, and the missing interval-deleted word fixed in both languages.

**فارسی.** ثبت مستقل کارکرد اعشاری و تاریخچهٔ آن اضافه شد؛ سررسید زمانی/کارکردی، مبنای نامعلوم، تاریخ آینده، حدود تقویم و تبدیل واحد اصلاح شد. ارز و دقت آن صریح، ارقام فارسی/عربی و جمع‌های بزرگ دقیق شدند. پیش‌نویس، بازیابی خطا، حذف گروهی و Undo دادهٔ خام و فرم‌های کوچک بهبود یافتند. در این مرحله: انتخاب و نمایش تاریخ با تقویم مشترک (شمسی برای فارسی)، یادداشت‌های چندخطی با ویرایشگر مشترک، یادآور اختیاری روی هر دستگاه با اطلاع‌رسانی خودش که با حذف/بایگانی دستگاه می‌رود، بازخورد بایگانی با بازگردانی، و اصلاح پیام «بازه حذف شد» در هر دو زبان.

## Platform requests

Fulfilled since the original request: shared Jalali date entry/display — both date pickers go through the platform's solar-capable calendar and every absolute date reads through the shared label, so the old "labelled Gregorian" fallback is retired; multiline note input — asset and service notes use the shared multiline editor; and optional notification scheduling — the platform's reminder control sits on an asset's page, wired to the record so its alert cancels with deletion or archiving, with its own notice in both languages.

Still requested, deliberately not faked: store transactions with cross-process conflict detection — the public store API still exposes no transaction, so writes stay serialized with the module-owned recovery journal and guarded Undo; receipt/photo attachment APIs — an on-open notice and entered text stand in, with no attachment permissions; live sensors remain outside scope.

## Checks

This review-and-upgrade pass, on the working tree at Flutter 3.35.5 / Dart 3.9.2: `dart format` clean on both module folders; `flutter analyze --fatal-infos` fully clean; the shared gate `test/module_kit_test.dart` 40 passed; `test/modules/maintenance` **99 passed** (86 inherited, all still green, + 13 added: reminder presence/clear/absent-on-archived/absent-on-missing, Jalali labels EN + FA with the retired annotations asserted gone, editor tooltips, the multiline note round-trip and editor params, the Persian interval-deleted notice, archive Undo, and deterministic same-instant orders); the l10n / text-field / sheet-swipe / motion scanners 17 passed. Both string maps hold 188 identical keys, no empty values, no bidi controls. No file over 400 lines (largest: controller 397, maintenance_screen 394). Edits confined to `lib/modules/maintenance` and `test/modules/maintenance`.

The original validation on Nex main `724b999a91c5b7366fbb4d9e8f17b36a3fb16318`, Flutter 3.35.5 / Dart 3.9.2, ran in a separate checkout with temporary registry entries: `flutter test --no-pub test/modules/maintenance test/module_kit_test.dart` **115 passed** (86 module tests + 29 shared gate tests as of that pass), covering the original cases, fractional/currency/date/unknown-baseline mathematics, current readings, post-write rollback, concurrent rule saves, exact raw compound Undo, parent guards, raw draft reopening and all four editors at 320×480 with 2× text and reduced motion in English light/Persian dark. Original screen cases additionally cover Persian light and English dark. Real-device testing remains outstanding; the shared reminder scheduling itself needs a rolled-out module and the notification permission, so tests observe the control, its notice and its stored/cleared reminder.
