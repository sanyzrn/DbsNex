# Parking

## What it does

A manual memory of where each vehicle is parked: place, floor, spot, landmark,
optional typed coordinates and paid-until time. One active session per normalized
vehicle name. Found my car preserves history; recent places prefill coordinates.
Search keeps at most eight distinct queries. The timer reads the clock while
visible and stops in background. This does not acquire GPS, show a map, photograph
a spot or schedule notifications.

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
Paid-until is a manual foreground calculation.

FA: «اینجا پارک کردم» را بزنید، محل و نشانه‌ها را بنویسید و ذخیره کنید.
برای همان خودرو، پارک قبلی را نگه دارید یا صریحاً ببندید و مورد تازه بسازید.
«ماشینم را پیدا کردم» آن را به گذشته می‌برد. حذف، بازگردانی دارد؛ اگر اطلاعات
بعداً تغییر کرده باشد بازگردانی متوقف می‌شود. پیش‌نویس را می‌توانید نگه دارید.
زمان پایان پارک دستی است و اعلان پس‌زمینه ندارد.

## Changelog

EN: Enforced one active parking per vehicle, including edits and Undo. Repaired
strict dates/coordinates, local expiry editing, exact history, bounded search,
fresh writes, rollback/recovery, drafts and visible storage failure. Improved
small-screen padding and long labels; retained FA/EN and light/dark.

FA: پارک فعال یکتا، تاریخ و مختصات معتبر، حفظ زمان دقیق هنگام ویرایش، جستجوی
بدون تکرار، ذخیره قابل‌بازیابی، پیش‌نویس و خطاهای قابل‌فهم اضافه یا اصلاح شد.

## Platform requests

Permission-gated location/maps, photos with backup lifecycle, opt-in local
notifications, a shared Jalali date/time picker and the conforming multiline
editor. Atomic compare-and-write/group transactions would harden multi-window
races. Current fallbacks remain useful without these APIs.

## Checks

Reviewed against main cad5fcaeaaa7ab489f48cfdf1b03add6b6623879 on Windows.
Flutter 3.35.5 / Dart 3.9.2; dependencies retain baseline versions/checksums.
Exact final counts, logs, visual captures and limitations are in
the phase's review/VALIDATION.md.

~~~text
flutter test --no-pub test/module_kit_test.dart test/modules/parking --reporter expanded
dart analyze --fatal-infos lib/modules/parking test/modules/parking
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
