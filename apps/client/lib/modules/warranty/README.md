# Warranty

## What it does

Records products and their user-supplied coverage, with category, brand/model,
serial/invoice reference, merchant, purchase date, optional amount and note.
Coverage comes from an explicit end date or visibly computed month duration.
Sections show covered, ending soon, expired and date unavailable. Search/sort,
archive and dated claim/service notes stay local. Receipt details are typed text;
no photo upload, no warranty authenticity or merchant acceptance, and no alert
unless the person sets the optional device reminder on a purchase's detail sheet.

## Records

- warranty v1: product/category/brand/model/serial/merchant/receiptRef/coverageType/
  note, purchasedAt, coverageEnd, archived; optional durationMonths and amountRials.
  Civil dates retain calendar components. Typed input is civil, years 1900–2100;
  the shared calendar button picks a Jalali day into the same civil format.
- claim v1: warrantyId, kind (claim/service), note, UTC at. Captured notes do not
  send a claim to a shop. History remains through edits/archive.
- draft v1: raw purchase/coverage/amount text and rial/toman selection, base
  fingerprint and stable recordId. Claim drafts also bind parentId and kind so
  another product's text is not accidentally applied. IDs use
  claim:<parentId>:<kind>:new; parent deletion/Undo includes those raw drafts.
- operation v1: raw before-images and durable committed marker for grouped
  writes/deletions/Undo. Recovery rolls back unfinished groups before new writes.

All kinds are module-local and included in core backups/remove-data behavior.
Edits change only fields edited by the user, merging into a fresh raw record.
Delete/Undo preserve unknown fields, related claims and the entry's draft.

## Decisions

Month duration means same day in the destination month, clamped to its final day:
Jan 31 + 1 month is Feb 28/29. Add from the purchase anchor, not a repeated rolling
month calculation. Duration is 1–2400 months and cannot end past year 2100.
Huge duration input is refused before DateTime arithmetic. End day is inclusive;
tomorrow after that date is expired. Civil UTC coordinates prevent DST-related
23/25-hour off-by-one day counts. Expired counts are negative internally, so the
UI says “Ended 12 days ago”, not “Ends today”. Missing/bad coverage is unavailable,
not expired or fabricated as today's date.

Impossible dates and both duration/end entered at once are rejected. Purchase
cannot follow end. Entry stays civil (`yyyy/MM/dd`, years 1900–2100): the shared
Jalali picker writes the civil day, and every date a person reads goes through
the shared label on their saved calendar — Jalali in Persian digits for a
Persian reader — while storage stays ISO 8601 civil. A stored UTC midnight is
rebuilt as a local civil day first, so it never reads as the day before it was
written. Unchanged stored dates stay exact; old missing purchase dates are not
filled with today. Editing such a record may require explicitly repairing its
date.

Money remains integer RIALS under the original Iranian-price contract. Toman
entry allows one decimal place exactly (1.5 toman = 15 rial), no rounding,
negative values, grouping ambiguity or overflow. Bound is 2^53−1. Toggling the
unit converts the current valid amount rather than reinterpreting the same digits.
No currency exchange rate or international amount is inferred; foreign currency
requires an explicit currency/schema feature rather than treating it as rials.
No new currency selector was added to this Iran-specific module.

Save completes inside editors, keeping text on failure. Checkpoints are raw and
coalesced; Keep draft & close waits for the latest write. Failed draft reads block
replacement. Claim save verifies the parent is still present, keeps its editor
open on failure and uses a stable ID for retry. Complete claim history is visible.

The public API has no transactions. Durable journal/rollback groups make local
compound delete/Undo recoverable. Independent external writers still need core
transactions/compare-and-write; serialization is per supplied store instance.
Guarded Undo refuses later conflicting content and shows an error.

Draft restoration merges raw user changes with fresh inventory/session/archive
state. Unedited fields retain newly changed values; progress does not invalidate
typed text. Quiet Back does not replace an unread or untouched checkpoint.

Legacy date-only fields containing ISO offsets retain the written civil day.
Claim `at` stamps remain actual UTC instants, shown as the local day they
happened; these two meanings are not conflated. Missing dates are never
invented.

## Guide

EN: Add a purchase, date and the maker/shop terms you know. Enter either months
or an end date and check the visible computed end. Type receipt/invoice reference;
choose rial/toman and verify the amount. Claim/service creates a dated local note.
Set the optional device alert before coverage ends or a claim is due.
Archive keeps history. Delete offers guarded Undo for the complete record set.

FA: خرید، تاریخ و شرایط اعلام‌شده فروشنده یا سازنده را بنویسید. مدت یا تاریخ
پایان را انتخاب کنید و تاریخ محاسبه‌شده را ببینید. شماره رسید را تایپ کنید؛
واحد ریال یا تومان و مبلغ را بررسی کنید. پیگیری و سرویس یادداشت محلی تاریخ‌دار
هستند. در صورت نیاز، هشدار گوشی را برای پایان گارانتی یا سررسید پیگیری
تنظیم کنید. آرشیو سابقه را نگه می‌دارد؛ حذفِ مجموعه، بازگردانی دارد.

## Changelog

EN: Added the optional device reminder on a purchase (the platform cancels it
with delete/archive), shared-calendar date reading on every visible date, the
note field's own label, an empty state that carries its own add button, and
honest wording — "Ended yesterday", "1 month", unknown-end rows no longer in
the expired glyph; the search field now follows the typed script and the
soonest sort keeps ties stable with unknown ends last. Preserved FA/EN and both
themes.

FA: هشدار اختیاری گوشی روی هر خرید اضافه شد (با حذف یا آرشیو خودکار لغو
می‌شود)؛ همهٔ تاریخ‌ها در تقویم ذخیره‌شدهٔ شما خوانده می‌شوند؛ یادداشت برچسب
گرفت؛ حالت خالی دکمهٔ افزودن خودش را دارد؛ واژه‌های «دیروز تمام شد» و «یک
ماه» اصلاح شد؛ جست‌وجو با متن فارسی درست کار می‌کند و مرتب‌سازیِ نزدیک‌ترین
پایان، ترتیب ثبت‌های برابر را حفظ می‌کند.

EN (2.1.x strict pass): Repaired strict dates, bounded month arithmetic,
inclusive day/DST calculations, expired-day text and unknown-date grouping.
Fixed exact fractional toman entry and unit conversion, fresh edits, claim
retry/orphan prevention, persisted drafts, compound recovery and guarded raw
Undo. Preserved FA/EN and both themes.

FA: تاریخ و مدت معتبر، روز پایان و شمارش روزها، تاریخ نامشخص، تبدیل دقیق ریال/
تومان، حفظ ویرایش تازه، پیش‌نویس و بازگردانی کامل خرید و پیگیری اصلاح شد.

## Platform requests

1. ~~Shared Jalali picker/formatter and multiline editor.~~ **Fulfilled:** the
   purchase and end-date fields wrap `NexModuleDateEntry` (typed civil entry
   plus the shared Jalali calendar button), and every date a person reads —
   list rows, detail rows, the editor's computed end, each claim note's day —
   goes through the shared `nexModuleDateLabel` on the saved calendar. The
   note and claim fields are the shared `NexTextField`; storage stays ISO
   8601 civil.
2. ~~Opt-in local notifications.~~ **Fulfilled:** `NexModuleReminderControl` sits
   on an active purchase's detail sheet, for the end of the coverage or a
   claim deadline, wired to that record so the platform auto-cancels when it
   is deleted or archived (archived purchases offer nothing). Scheduling
   itself still needs the notification permission and rollout; nothing is
   ever scheduled on the module's own.
3. Approved photo/receipt attachments with backup/delete lifecycle — still
   requested; the receipt reference remains typed text, and the editor says so.
4. Secure export — still requested.
5. Transactions/compare-and-write — still requested; the durable journal keeps
   local compound delete/Undo recoverable meanwhile.

No hidden network or private-core access.

## Checks

Reviewed and upgraded in this pass (Linux sandbox, Flutter 3.35.5 / Dart
3.9.2). `dart format` clean; `flutter analyze --fatal-infos` clean; gate
`test/module_kit_test.dart` 40 passed; `test/modules/warranty` 81 passed
(68 inherited, all still green, + 13 added: reminder presence/clear/absence,
empty-state add, Jalali labels fa+en, no-Gregorian guard, computed-end label,
unknown-end grouping, "Ended yesterday", "1 month", Today-chip padding,
dateText padding, sort ties); shared scanners l10n / text_field_rule /
sheet_swipe / motion 17 passed. No file over 400 lines (max 375); en/fa string
parity 96/96, no bidi controls. Reminder scheduling itself needs device
permission and rollout, so the tests observe the control, its Clear and the
stored `__reminder` record rather than an OS notification.

~~~text
flutter test --no-pub test/module_kit_test.dart test/modules/warranty --reporter expanded
dart analyze --fatal-infos lib/modules/warranty test/modules/warranty
dart format <this module lib and test paths>
~~~

Tests include unit calculations/invalid/huge values, full existing flows, storage
read/write faults, interrupted-group recovery, raw Undo, drafts, isolation,
reopen, FA/EN, real Nex light/dark, 320×480 at scale 2 and reduced motion.
Captured screens are Flutter widget renders with synthetic data, not device
screenshots. Android/iOS permissions, native keyboard, TalkBack/VoiceOver and
platform release builds still need maintainer/device acceptance.

The earlier Windows pass (main cad5fcae) covered the strict-date, month-math,
toman and journal work and kept its own counts; its logs and captures are in
that phase's review/VALIDATION.md. Only module lib/test directories are
touched by this pass; the module stays registered exactly as the gate found
it. No core/API/catalog/ARB/dependency source, Commit, Push, ZIP or external
message is delivered.
