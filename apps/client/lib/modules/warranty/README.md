# Warranty

## What it does

Records products and their user-supplied coverage, with category, brand/model,
serial/invoice reference, merchant, purchase date, optional amount and note.
Coverage comes from an explicit end date or visibly computed month duration.
Sections show covered, ending soon, expired and date unavailable. Search/sort,
archive and dated claim/service notes stay local. Receipt details are typed text;
no photo upload, warranty authenticity/merchant acceptance or background alert.

## Records

- warranty v1: product/category/brand/model/serial/merchant/receiptRef/coverageType/
  note, purchasedAt, coverageEnd, archived; optional durationMonths and amountRials.
  Civil dates retain calendar components. New input is Gregorian, years 1900–2100.
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
cannot follow end. Gregorian input is disclosed; no Jalali formatter is invented.
Unchanged stored dates stay exact; old missing purchase dates are not filled with
today. Editing such a record may require explicitly repairing its date.

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

Legacy date-only fields containing ISO offsets retain the written Gregorian
day. Dose/claim/session timestamps remain actual UTC instants; these two
meanings are not conflated. Missing dates are never invented.

## Guide

EN: Add a purchase, date and the maker/shop terms you know. Enter either months
or an end date and check the visible computed end. Type receipt/invoice reference;
choose rial/toman and verify the amount. Claim/service creates a dated local note.
Archive keeps history. Delete offers guarded Undo for the complete record set.

FA: خرید، تاریخ و شرایط اعلام‌شده فروشنده یا سازنده را بنویسید. مدت یا تاریخ
پایان را انتخاب کنید و تاریخ محاسبه‌شده را ببینید. شماره رسید را تایپ کنید؛
واحد ریال یا تومان و مبلغ را بررسی کنید. پیگیری و سرویس یادداشت محلی تاریخ‌دار
هستند. آرشیو سابقه را نگه می‌دارد؛ حذفِ مجموعه، بازگردانی دارد.

## Changelog

EN: Repaired strict dates, bounded month arithmetic, inclusive day/DST calculations,
expired-day text and unknown-date grouping. Fixed exact fractional toman entry
and unit conversion, fresh edits, claim retry/orphan prevention, persisted drafts,
compound recovery and guarded raw Undo. Preserved FA/EN and both themes.

FA: تاریخ و مدت معتبر، روز پایان و شمارش روزها، تاریخ نامشخص، تبدیل دقیق ریال/
تومان، حفظ ویرایش تازه، پیش‌نویس و بازگردانی کامل خرید و پیگیری اصلاح شد.

## Platform requests

Approved photo/receipt attachments with backup/delete lifecycle, shared Jalali
picker/formatter and multiline editor, opt-in local notifications, secure export,
and transactions/compare-and-write. Current typed reference and foreground status
work without them; no hidden network or private-core access.

## Checks

Reviewed against main cad5fcaeaaa7ab489f48cfdf1b03add6b6623879 on Windows.
Flutter 3.35.5 / Dart 3.9.2; dependencies retain baseline versions/checksums.
Exact final counts, logs, visual captures and limitations are in
the phase's review/VALIDATION.md.

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

Windows plugin symlink setup lacks Developer Mode; tests use --no-pub with the
resolved package configuration. No OS setting was changed. Only module lib/test
directories are delivered. Registry registration is temporary for the gate and
restored. No core/API/catalog/ARB/dependency source, Commit, Push, ZIP or external
message is delivered. Maintainer registers the const module, retires its planned
entry and integrates the Guide/Changelog before release.
