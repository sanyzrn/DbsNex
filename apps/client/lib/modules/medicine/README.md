# Medicine

## What it does

A personal list of exactly user-entered medicine names, strength/package,
instructions, reference times/days and private notes. Quantity, dose-unit count,
expiry and refill threshold are optional. Taken/Skipped are explicit manual logs.
Archive retains history. No drug database, clinical dose suggestion, interaction
check, missed-dose inference or safety certification. Nothing is scheduled on
its own: the only reminder is the explicit one-time OS alert a person sets by
hand on a medicine's detail sheet, and it runs only once the module's rollout is
enabled.

## Records

- medicine v1 readable; current saved form v2: name, strength, package, instructions,
  times, days, purpose, archived; optional quantity, doseUnits, expiresAt,
  refillThreshold and stockEpoch. Expiry is a calendar date represented by the
  supplied Gregorian date components; never shifted as an elapsed-time deadline.
- dose v1 readable; new v2: medicineId, action, UTC at, actual takenUnits (when
  positive), stockDelta, stockEpoch and stockLimited. Missing stockDelta in a v2
  log is not guessed. Skipped never changes quantity.
- draft v1: raw fields/unfinished time, times choice list, baseline fingerprint,
  stable target recordId. Separate from saved medicine, included in delete/Undo.
- operation v1: raw before-images and committed marker. Interrupted uncommitted
  groups roll back on read/reopen; committed groups only clean up the journal.

All records follow Nex module backup/remove-data behavior. This module does not
claim additional encryption absent a platform API. Test data uses neutral
examples. No medicine names/content are exposed to other modules or analytics.

## Decisions

Stock uses consistent user-defined integer units only, bounded by 2^53−1.
A Taken log subtracts min(quantity, doseUnits), stores that actual deduction and
marks insufficient recorded inventory. It does not judge whether the dose was
medically appropriate. Correcting the log restores only the stored deduction;
dose and quantity change in one recoverable operation. Undo is guarded against
later changes. Unknown quantity/unit means no automatic stock adjustment.

A manual recount or package/unit change starts a new stockEpoch. Corrections
from an older baseline remove their log but do not alter the new recount.
Changing doseUnits does not rewrite historical actual deductions. Text-only edits
merge changed fields into a fresh raw body, preserving current stock/history and
unknown fields. Archived/deleted parents cannot acquire new logs.

Legacy v1 logs use their stored takenUnits only while the inventory has no newer
epoch. Earlier versions could record the requested amount despite clamping stock
to zero; that historical loss cannot be reconstructed reliably. No retroactive
invented correction is applied. Review/recount legacy stock manually when needed.

The public store has no transaction. Groups use a durable journal and rollback;
failed rollback remains pending for recovery. Serialization is per passed store
instance. Platform transactions/compare-and-write are needed for independent
external writers. Undo conflicts are visible and do not overwrite later content.

Impossible dates, malformed/negative/overflow counts, invalid refill threshold
and impossible times are rejected, each in its own field's words. Arabic/Persian
digits work. A valid time still in the entry box is included on Save. The
expiry is entered as a civil `yyyy/MM/dd` day (1900–2100, the calendar's own
range, so a Persian year such as 1405 is never stored as the civil year 1405)
or picked from the shared calendar button on the person's saved calendar;
it is stored as civil ISO 8601 and read back through the shared date label —
Jalali in Persian digits for a solar-calendar reader, the civil day otherwise.
The supplied expiry date is shown, with the existing
conservative today-or-earlier marker; this is not a medical safety decision.

Editors checkpoint raw text/times, offer Keep draft & close, and save before
closing. Read failures cannot replace a prior draft. Failed saves keep input.
History is complete, not silently limited to the newest thirty visible logs.
Stock limitation is disclosed on the affected log. Reopening/resuming refreshes
date/refill indicators. Correcting a dose is not an instruction to take another.

Draft restoration merges raw user changes with fresh inventory/session/archive
state. Unedited fields retain newly changed values; progress does not invalidate
typed text. Quiet Back does not replace an unread or untouched checkpoint.

Legacy date-only fields containing ISO offsets retain the written Gregorian
day. Dose timestamps remain actual UTC instants; these two
meanings are not conflated. Missing dates are never invented.

## Guide

EN: Add the name and details you know, optionally quantity and consistent units.
Reference times remain notes. A separate explicit one-time OS reminder control uses the shared module API; it does not infer a dose schedule. The module remains Soon, so no reminders run until its rollout is enabled. Taken or Skipped records your
choice. Delete a mistaken log to correct it; Undo restores it if data has not
changed. A recount starts a fresh inventory baseline. A clinician or pharmacist
is the source for medication instructions.

FA: نام و جزئیات دارو را مطابق نوشته خودتان ثبت کنید. مقدار و واحد موجودی
اختیاری است. ساعت‌ها فقط برای مراجعه‌اند و یادآور نیستند. یادآور یک‌باره هم
دستی است: از صفحه جزئیات دارو خودتان تنظیمش می‌کنید و برنامه از خود چیزی
زمان‌بندی نمی‌کند. مصرف یا ردکردن را
دستی ثبت کنید؛ حذف گزارش اشتباه اصلاح آن است و بازگردانی دارد. شمارش دوباره
موجودی، مبنای تازه می‌سازد. دستور پزشکی را از پزشک یا داروساز بگیرید.

## Changelog

EN: Fixed partial stock deductions/corrections, grouped stock/log recovery,
recount isolation, stale edits, compound raw Undo, dates/time/refill parsing,
unfinished-time save, persisted drafts and honest read/write retry. Preserved
archive history and module privacy; added complete history and actual expiry.
Dates now enter through the shared Jalali calendar entry and read back on the
person's own calendar — Jalali in Persian digits on the solar calendar, the
civil day otherwise — with storage unchanged as civil ISO 8601. The empty
cabinet carries its own add button, an impossible expiry says so in its own
words, the expiry label no longer forces a Gregorian note, and twelve unused
words plus dead helpers were removed.

FA: موجودی و اصلاح مصرف، حفظ شمارش تازه، بازگردانی کامل، تاریخ و ساعت معتبر،
ذخیره ساعت ناتمام، پیش‌نویس و خطاهای قابل‌تلاش اصلاح شد؛ سابقه و حریم خصوصی
ماژول حفظ شده است. ورود تاریخ انقضا از تقویم مشترک و خواندن آن در تقویم
خود خواننده انجام می‌شود — جلالی با ارقام فارسی — و ذخیره همان تاریخ
میلادی ISO باقی می‌ماند. کادر خالی دکمهٔ افزودن خودش را دارد، تاریخ
نادرست با پیام خودش می‌گوید و واژه‌ها و کدهای بی‌استفاده حذف شدند.

## Platform requests

Fulfilled, in the tree:

- Reviewed opt-in local notifications with permission/denial handling — the
  shared `NexModuleReminderControl` sits on an active medicine's detail sheet;
  an archived medicine offers none, and the platform cancels reminders on
  archive, delete and module removal.
- Shared Jalali date entry and display — `NexModuleDateEntry` wraps the expiry
  field (typed civil `yyyy/MM/dd` or the shared calendar button), and every
  absolute date a person reads — the expiry day and each dose log — goes
  through `nexModuleDateLabel`. Storage stays civil ISO 8601.
- Shared multiline editor — instructions and the private note use
  `NexTextField`; one-line fields stay inside `NexAutoDirection`.

Still requested:

- Secure storage integration as required by core policy.
- Permission-gated photos/scan with backup retention.
- Atomic record-group/compare-and-write support for independent external
  writers. Until then the module serialises its own writes and journals its
  groups for rollback.

No clinical database/dosing API requested or improvised by this module.

## Checks

Completed in this pass (module review 5-b, Linux, Flutter 3.35.5 / Dart 3.9.2):
`dart format` over the module's lib and test folders — 0 changed;
`flutter analyze --fatal-infos` — No issues found; the module gate
`test/module_kit_test.dart` — 40 passed; `flutter test test/modules/medicine
-j 2` — 81 passed (74 inherited, every one kept green, 7 added). No file over
400 lines (max 376). Both language maps hold the same 82 keys; no bidi control
characters in the Persian words.

Previously reviewed against main cad5fcaeaaa7ab489f48cfdf1b03add6b6623879 on
Windows. Dependencies retain baseline versions/checksums. Exact final counts,
logs, visual captures and limitations of that pass are in
the phase's review/VALIDATION.md.

~~~text
flutter test --no-pub test/module_kit_test.dart test/modules/medicine --reporter expanded
dart analyze --fatal-infos lib/modules/medicine test/modules/medicine
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
