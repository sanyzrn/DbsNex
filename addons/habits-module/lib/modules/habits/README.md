# Habits

## 1. What it does

Today lists active habits with a clear, semantic 48dp completion toggle and
a daily count. Detail shows a forgiving streak, weekly target progress, the
last 14 days, completion total, note and recent check-ins. Create/edit supports
daily or 1–7 times per week. Archive/unarchive keeps history; delete has Undo.
The settings action selects any of seven start days for all weekly summaries.
Empty, archived, loading and retry states have working actions.
Compact/large-text forms use wrapping choices. Screens refresh on store changes
and device resume; date labels are also recalculated on interaction/reopening.
There are no reminders, widgets, social features, network calls or AI features.

## 2. Records

Kind `habit`, store-generated stable ID:

```json
{"name":"Morning stretch","note":"5 minutes","schedule":"weekly","target":3,"archived":false,"createdAt":"2026-10-12T08:00:00.000"}
```

`name`/`note`: string; `schedule`: daily/weekly; `target`: integer 1–7
(1 for daily); `archived`: boolean; `createdAt`: ISO timestamp. Legacy/default
values are empty text, daily, target 3 (weekly) / 1 (daily), false, epoch.
Editing preserves identity/history and archive state. The habit/check shape
remains version 1 without a version field, for compatibility.

Kind `check`, deterministic ID `<habit-id>:<YYYY-MM-DD>`:

```json
{"habit":"h1","date":"2026-10-12","at":"2026-10-12T08:30:00.000"}
```

`habit`: parent ID string; `date`: local civil date; `at`: ISO timestamp.
An invalid date reads as unknown (`""`), never today. Full ISO historical date
strings are normalized to their civil-date prefix; impossible dates are ignored.
Invalid `at` reads as epoch. Future checks are kept but excluded from every
count and the displayed recent history. Duplicate civil dates count only once.

Kind `settings`, stable ID `week`:

```json
{"v":1,"firstDay":1}
```

`firstDay`: Dart weekday 1 Monday … 7 Sunday, default **6 Saturday**.
The default preserves old summaries in both languages. It is explicitly chosen
inside this module and does not read/change any Nex preference.

Drafts are stored under kind `draft`, IDs `<editor>:<record-id>` or
`<editor>:new`, with `{v: 1, base: <JSON string of original body>, fields: {...}}`.
Field values are strings from the editors plus typed choices described below.
`fields.recordId` is an optional stable target ID for new records: if that record
already exists, a leftover checkpoint is not reopened as a new unsaved record.
A cleanup failure may replace the draft with `{v: 1, discarded: true}`; this
marker has no fields/base and is ignored on read.
`fields.recordId` is an optional stable target ID for new records: if that record
already exists, a leftover checkpoint is not reopened as a new unsaved record.
A cleanup failure may replace the draft with `{v: 1, discarded: true}`; this
marker has no fields/base and is ignored on read.
`fields.recordId` is an optional stable target ID for new records: if that record
already exists, a leftover checkpoint is not reopened as a new unsaved record.
A cleanup failure may replace the draft with `{v: 1, discarded: true}`; this
marker has no fields/base and is ignored on read.
Serial, coalesced writes keep the latest snapshot; back/swipe keeps it, explicit
Cancel discards it, successful Save clears it. A baseline fingerprint rejects
stale drafts after a final record changes. These records stay in this module's
store/backups and never count toward progress or balances.

Habit draft fields: `name`, `note` strings; `weekly` boolean; `target` integer.

Compound deletion uses kind `operation`, ID `<parent-kind>:<parent-id>`, body
`{v: 1, records: [{kind: string, id: string, body: JSON object}, ...]}`.
A complete raw snapshot (children, related edit draft, then parent) is written
before deletion. After success the journal is removed. A failed/interrupted
deletion is restored on the next read. Undo restores raw bodies including
unknown historical fields. The store supplies new `updatedAt` values; original
record IDs and all body data are retained. Atomic transactions are not exposed
by the kit: the recovery journal is the bounded offline fallback.

## 3. Decisions

- Civil-day arithmetic uses UTC calendar midnights after extracting local
  year/month/day. A late-night and early-morning check are distinct days;
  DST never changes a day/week count. No 24-hour subtraction defines a check.
- A streak is the most recent run of completed intervals with **at most one
  missed interval in the entire run**, not one per gap. A completed interval
  is one checked day (daily) or a week meeting its target (weekly).
- Today/current week may remain pending. Latest completion in this interval
  or the previous one keeps the run; two intervals back uses the single grace
  now. Three intervals back ends the displayed streak. Walking back stops at
  a second missed interval, even when the misses are separated by completions.
- Grace counts zero completed intervals. `graceNow` is the current allowance;
  `graceInside` identifies a forgiven gap between completions. A pending grace
  cannot additionally forgive a historical gap. Old history is never erased.
- Changing week start recalculates all weekly groupings/streaks while preserving
  every check-in. Language changes do not change this persisted boundary.
- Malformed checks cannot fabricate progress; a zero current streak with earlier
  history says “A fresh start today”, rather than “No check-ins yet”.
- Forms checkpoint locally as typed; errors leave input intact and permit retry.
  Writes use stable IDs and double taps are guarded. No data leaves the module.

## 4. Guide

**English:** Add one small habit, daily or with a weekly target, then check it
off with one tap. Your streak counts what you completed and can forgive one
missed day or week, clearly labelled. Choose your week start in the module's
settings. Archive to take a break without losing history. Delete has Undo;
leaving an unfinished editor keeps a local draft.

**فارسی:** یک عادت کوچک با برنامهٔ روزانه یا هدف هفتگی بسازید و با یک لمس
انجامش را ثبت کنید. آمار تداوم فقط کارهای انجام‌شده را می‌شمارد و برای یک
روز یا هفتهٔ جاافتاده، فرصت جبران مشخصی دارد. روز شروع هفته را از تنظیمات
ماژول انتخاب کنید. بایگانی، تاریخچه را نگه می‌دارد؛ حذف با بازگردانی همراه
است و ورودیِ فرم ناتمام به‌صورت پیش‌نویس محلی می‌ماند.

## 5. Changelog

- EN: Habits: configurable week start, deterministic single-grace streaks,
  honest historical checks, recoverable drafts and accessible compact forms.
- FA: عادت‌ها: تنظیم روز شروع هفته، فرصت جبران دقیق، اصلاح ثبت‌های تاریخی،
  پیش‌نویس قابل‌بازیابی و فرم‌های مناسب صفحهٔ کوچک و متن بزرگ.

## 6. Platform requests

1. Shared Jalali date picker/formatter through `module_api.dart`. The kit exposes
   no calendar API; the module uses truthful relative dates rather than a
   Gregorian calendar labelled as Jalali.
2. `NexTextField` exported through the module API. Notes use the permitted
   Flutter multiline equivalent inside `NexAutoDirection`; stored prose uses
   the exported content-direction helper. Nex's native per-paragraph editor
   is unavailable. The full-app multiline-field scanner demands that private
   widget, conflicting with the module import boundary; see validation report.
3. Optional atomic batch storage for parent/child changes. The local recovery
   journal currently protects interrupted compound deletion without bypassing
   `NexModuleStore`.

## 7. Checks

Reviewed in the owner's Windows / PowerShell workspace against Nex `main`
`fdd70f4890b0bab67d30b88d4821273113d4b01d`, with the repository's pinned Flutter **3.35.5** / Dart **3.9.2**.
The installed system Flutter is 3.44.8; a local validation SDK was used instead.

All three modules were temporarily registered in a separate reference checkout
under `.validation/DbsNex`; the original registry is restored after checks.
No core source, ARB, dependencies, registry or planned-catalog edits are delivered.
No Commit, Push, PR, remote write or ZIP was made. `core.longpaths` was supplied
to clone per command rather than changing the owner's global Git configuration.

Commands run from `apps/client` (with the pinned local SDK):

```text
flutter pub get --enforce-lockfile
flutter test --no-pub test/module_kit_test.dart test/modules/habits test/modules/smoke_free test/modules/lent_borrowed --reporter expanded
flutter analyze --no-pub --fatal-infos
flutter test --no-pub --reporter expanded
dart format <module's lib and test folders>
```

`--no-pub` follows successful dependency resolution: Flutter's final Windows
plugin-symlink setup reports missing Developer Mode privileges. Package versions
remain exactly those in the baseline lockfile; only the hosted download endpoint
was changed temporarily to the public Flutter mirror because pub.dev returned
403. Tests run outside the filesystem sandbox after its compiler-temp-file copy
failed with Access denied. Neither workaround changes module code or dependencies.

Final results: **248/248 passed** for the combined module tests and the real
module-kit gate with temporary registration; **full client analyzer clean**.
The full client run reported **1368 passed, 4 failed, 3 skipped**: two Windows
attachment-fixture file-lock cleanup failures, the intentional old planned
Habits entry pending maintainer integration, and the multiline editor/API
discrepancy described above. The Windows failures reproduced with the original
registry. Core: 231 passed/analyzer clean. Data: 253 passed, 2 failed (Windows
symlink privileges), 14 skipped/analyzer clean. Final detailed evidence is in
`review/VALIDATION.md` at the workspace root. Earlier test failures were repaired;
the final log, not the initial README's historical claims, is authoritative.

Tests include Persian RTL and English LTR, light/dark, text scale 2.0 at 320×640,
reduced motion, reopening, isolation, failed writes/retry, draft coalescing,
back waits for the latest durable checkpoint, retry after a failed flush,
and meaningful user journeys. Actual Flutter main-screen captures use Nex's
themes and bundled fonts in Persian dark and English light, under
`review/screenshots`. These are widget renders with test fixtures, not Android-device screenshots.

Maintainer integration: register the three const modules and imports in
`nexModules`; remove the old planned IDs **`habits`, `smoke-free`, `lent`**
(different from the actual IDs `habits`, `smoke_free`, `lent_borrowed`).
Copy the Guide/Changelog paragraphs above into the app's content. Run the gate,
full app checks and device/accessibility review before release.
