# Parking

## What it does

A manual memory of where each vehicle is parked: place, floor, spot, landmark,
optional typed coordinates and paid-until time. One active session per normalized
vehicle name. Found my car preserves history; recent places prefill coordinates.
Search keeps at most eight distinct queries. The timer reads the clock while
visible and stops in background. Dates are entered on the shared module
calendar (Jalali for a Persian solar-calendar reader) beside the typed civil
field, and every open parking and its detail view offer an **opt-in device
reminder** — an explicit one-time OS alert for when paid time runs out or the
person needs the car; the platform cancels it automatically when the record
goes away or the parking is found. This does not acquire GPS, show a map or
photograph a spot.

## Records

- session v1: vehicle, place, floor, spot, landmark, startedAt; optional foundAt,
  expiresAt, lat/lng. Newly written instants are UTC ISO strings. Legacy timestamps
  without an offset retain the old local interpretation; the original zone cannot
  be recovered. Edits preserve unchanged original instants/coordinate precision.
- place v1: place/floor/spot/landmark, bounded useCount, UTC lastUsedAt, optional
  validated coordinates. Updated from fresh store data.
- search v1: query, UTC at. Case-insensitive dedup, stable ID for a repeated query,
  actual stored cap eight.
- draft v1: separate raw fields, base JSON fingerprint and stable target recordId,
  including the new parking's initial startedAt. Kept drafts resume; failed draft
  reads block replacement. Stale drafts and already saved new entries do not apply.
- operation v1: raw before-image list and committed flag for a local write group.
  This is a recovery journal, not an API transaction. An interrupted uncommitted
  group rolls back on the next read; a committed group only cleans its journal.

All kinds stay inside this module and follow core backup/remove-data policy.
Unknown fields are preserved on edits/Undo. Delete includes the entry's draft.
History clear is one journaled group with one guarded Undo.

## Decisions

Keep earlier cancels the new write and leaves its editor open; Close earlier
closes fresh conflicting sessions and saves the replacement in one recoverable
group. Renaming an existing active entry performs the same conflict check.
A failed storage group restores before-images; if rollback itself fails, the
journal remains and Retry/reopen repairs it before further writes.

Undo refuses to overwrite later changes. Undo of a deleted active entry also
refuses when that vehicle already has another active session. Local serialization
is per provided store instance; simultaneous external writers need platform
compare-and-write/transaction support. This limitation is not hidden as full ACID.

Vehicle matching folds case and internal whitespace, with no transliteration.
Missing/invalid dates produce an unavailable label; invalid foundAt is not silently
reopened. Impossible dates, invalid coordinate text, non-finite/out-of-range
coordinates and impossible times are rejected. New input years are 1900–2100.
Gregorian manual date/time entry is explicit; expiry prefill uses local wall time
and unchanged edits keep the exact stored seconds/offset. Durations are instants;
negative/corrupt chronology is not shown as a meaningful measured duration.

Saving happens inside the sheet; failed writes preserve input and allow Retry.
Raw checkpoints are coalesced as typed. Back asks whether to discard, while
Keep draft & close waits for the latest checkpoint. A draft is not a saved parking.
History is ordered by startedAt rather than the date of editing.

Draft restoration merges raw user changes with fresh inventory/session/archive
state. Unedited fields retain newly changed values; progress does not invalidate
typed text. Quiet Back does not replace an unread or untouched checkpoint.

## Guide

EN: Tap Parked here, type the place and any clues, then Save. Keep the older
parking or explicitly close it if the vehicle already has an active entry.
Found my car closes it. Open history to edit or delete; Undo restores only when
it will not overwrite later data. Keep draft & close returns later to raw input.
Paid-until is a manual foreground calculation — and if you want an alert when it
runs out, set the opt-in reminder beside it once; it fires even with the app
closed and disappears with the parking.

FA: «اینجا پارک کردم» را بزنید، محل و نشانه‌ها را بنویسید و ذخیره کنید.
برای همان خودرو، پارک قبلی را نگه دارید یا صریحاً ببندید و مورد تازه بسازید.
«ماشینم را پیدا کردم» آن را به گذشته می‌برد. حذف، بازگردانی دارد؛ اگر اطلاعات
بعداً تغییر کرده باشد بازگردانی متوقف می‌شود. پیش‌نویس را می‌توانید نگه دارید.
زمان پایان پارک دستی است؛ اگر می‌خواهد سررسیدش خبرتان کند، یادآوری اختیاریِ
کنارش را یک بار تنظیم کنید — حتی با بسته‌بودن برنامه صادر می‌شود و با پارک
پاک می‌شود.

## Changelog

EN: Enforced one active parking per vehicle, including edits and Undo. Repaired
strict dates/coordinates, local expiry editing, exact history, bounded search,
fresh writes, rollback/recovery, drafts and visible storage failure. Improved
small-screen padding and long labels; retained FA/EN and light/dark. Upgraded:
shared Jalali calendar entry beside every typed date, the conforming shared
multiline editor for notes and clues, and an opt-in device reminder on the open
parking and its detail view.

FA: پارک فعال یکتا، تاریخ و مختصات معتبر، حفظ زمان دقیق هنگام ویرایش، جستجوی
بدون تکرار، ذخیره قابل‌بازیابی، پیش‌نویس و خطاهای قابل‌فهم اضافه یا اصلاح شد.
ارتقا: ورودی تاریخ روی تقویم مشترک با پشتیبانی جلالی، ویرایشگر متنی مشترک
برای یادداشت‌ها، و یادآوری اختیاریِ دستگاه برای پارکِ باز و صفحهٔ جزئیات.

## Platform requests

Fulfilled by the platform since 2.1.3 and used here: **opt-in local
notifications** (`NexModuleReminderControl` on the open parking and its detail
view — the platform auto-cancels when the record is removed, and Found my car
clears it), the **shared Jalali date picker/label** (`NexModuleDateEntry`,
`nexModuleDateLabel`) on every date the person enters or reads, and the
**conforming multiline editor** (`NexTextField`) for notes and clues.

Still requested: permission-gated location/maps and photos with backup
lifecycle (the module keeps typed coordinates and text clues without them),
and atomic compare-and-write/group transactions for multi-window races (serial
writes, fresh reads and the recovery journal remain the honest fallback).

## Checks

Upgraded against Nex `main` `f196440` (v2.1.8) with Flutter **3.35.5** /
Dart **3.9.2** on Linux. All edits stay inside `lib/modules/parking/` and
`test/modules/parking/`. The original Windows review against `cad5fca`
remains the module's first-pass record; its detailed evidence lives in that
phase's review/VALIDATION.md.

Commands run from `apps/client` on this upgrade pass:

~~~text
flutter pub get
dart format lib/modules/parking test/modules/parking
flutter analyze --fatal-infos
flutter test test/module_kit_test.dart -j 2
flutter test test/modules/parking -j 2
~~~

Final results: analyzer **clean**; format **0 changed**; module-kit gate
**40/40**; module tests **100/100 passed** — including the reminder control's
presence and clear flow, Jalali entry beside the typed date, storage faults,
interrupted-group recovery, raw Undo, drafts, isolation, FA/EN, light/dark,
320×480 at scale 2.0 and reduced motion. Android/iOS permissions, native
keyboard, TalkBack/VoiceOver and platform release builds still need
maintainer/device acceptance.

## Sharing where the car is (2.1.13)

The detail page can **share where the car is** as text: vehicle, place, floor,
spot, landmark and the time it was parked, as written, and a map link only when
both coordinates were typed and are real. Shared only by a tap.
