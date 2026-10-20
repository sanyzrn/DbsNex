# Habits

## 1. What it does

Today lists active habits with a clear, semantic 48dp completion toggle and
a daily count. Detail shows a forgiving streak, weekly target progress, the
last 14 days with their calendar range, completion total, the habit's start
day, note and recent check-ins. Recent check-ins keep relative words where
they read best and carry the platform calendar's own date beside them
(`nexModuleDateLabel`), so a Persian reader sees Jalali — never a Gregorian
date labelled as one. Create/edit supports daily or 1–7 times per week.
Archive/unarchive keeps history; delete has Undo — and so does taking a
day's check-in back, which restores the exact original record.
The settings action selects any of seven start days for all weekly summaries.
Empty, archived, loading and retry states have working actions — the empty
archive says where archiving happens and carries the way back to Today — and
the long empty states scroll rather than clip at large text.
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
- Every date a person reads is drawn by the platform calendar formatter
  (`nexModuleDateLabel`): each check-in history row, the two-week window's
  range and the habit's start day (`createdAt`). Relative words stay where
  they read best — today, yesterday, N days ago — with the absolute day
  beside them. Storage never changes: keys stay civil, timestamps stay
  ISO 8601, and a UTC key is rebuilt as a local civil day before it is
  labelled, so a western time zone never prints the day before. An unknown
  (epoch) creation date shows nothing rather than a wrong day.
- Forms checkpoint locally as typed; errors leave input intact and permit retry.
  Writes use stable IDs and double taps are guarded. No data leaves the module.
- Taking a check-in back is the one delete an accidental tap can cause. Its
  snackbar Undo writes the exact original record — same id, same day, same
  original moment — so an accidental removal never rewrites when it happened.
  Habits and check-ins order newest-first with an id/timestamp tiebreak, so
  equal or legacy records keep one stable order instead of shuffling per load.

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
- EN: Habits: calendar-true dates — each check-in day, the two-week range and
  the habit's start day now shown in the platform's own calendar, Jalali
  included.
- FA: عادت‌ها: تاریخ‌ها حالا با تقویم خود پلتفرم — از جمله جلالی — دیده
  می‌شوند؛ روزِ هر ثبت، بازهٔ دوهفته و روز شروع عادت.
- EN: Habits: removing a day's check-in now offers Undo, restoring the exact
  original record — the day and the moment it was first made.
- FA: عادت‌ها: برداشتن ثبتِ روز حالا با «بازگردانی» همراه است و همان ثبتِ
  اصلی — با همان روز و همان لحظهٔ نخست — برمی‌گردد.

## 6. Platform requests

1. ~~Shared Jalali date picker/formatter through `module_api.dart`.~~
   **Fulfilled:** the kit exports `NexModuleDateEntry`, `nexPickModuleDate`
   and `nexModuleDateLabel`. Every date this module shows — each history
   row, the two-week window, the habit's start day — goes through
   `nexModuleDateLabel`, so Jalali reads as Jalali. The module has no date
   a person types (the one-tap check-in is always today), so there is no
   field to wrap in `NexModuleDateEntry`; relative wording stays where it
   reads best. Civil storage keys and ISO timestamps are unchanged.
2. ~~`NexTextField` exported through the module API.~~ **Fulfilled:** the
   note field uses the exported `NexTextField`; the name stays one line
   inside `NexAutoDirection`; the stored note reads through
   `NexTextDirection`.
3. Optional atomic batch storage for parent/child changes. The local recovery
   journal currently protects interrupted compound deletion without bypassing
   `NexModuleStore`.

## 7. Checks

Current pass (this repository, this folder only), run from `apps/client`
with the repository's pinned Flutter **3.35.5** / Dart **3.9.2**:

```text
dart format lib/modules/habits test/modules/habits        # no diff
flutter analyze --fatal-infos                             # clean
flutter test test/module_kit_test.dart -j 2                # gate green
flutter test test/modules/habits -j 2                       # all green
```

The module's two folders are the only changes; no core source, ARB,
dependency, registry or rollout edits are involved. Exact counts are in
the shared worklog entry for this pass.

Tests cover Persian RTL and English LTR, light/dark, text scale 2.0 at
320x640, reduced motion, reopening, store isolation, failed writes with
retry, draft coalescing, back waiting for the latest durable checkpoint,
retry after a failed flush, interrupted compound deletion with exact-body
recovery, check-in removal with exact-record Undo from both the Today list
and the detail page, the archive screen's empty-state action, the
Jalali/Gregorian display of every absolute date, and
meaningful user journeys. Persian strings carry no bidi control
characters; every icon-only button has a tooltip; the progress rows carry
Semantics labels.

## 2.1.11 changes

- 2.1.11: optional daily reminder per habit (switch + time on the habit's page); one primary action on an empty page.

## Calendar and how often (2.1.13)

The detail page has a month calendar in the calendar the person reads (Jalali
or Gregorian, weeks starting on the chosen first day). A tap on any day up to
today makes that day's check-in — the same record, `<habit-id>:<YYYY-MM-DD>`,
as the Today button — and a tap on a marked day takes it back, with Undo. A
day to come cannot be marked; a day before the habit began can. **How often**
counts days checked of the days since the habit began (7, 30 and 90 days, the
window cut to the habit's life) for a daily habit, and weeks that met the
target among the last twelve *finished* weeks for a weekly one; the week in
progress and a first week that began mid-week are never counted against it.
Streaks and the forgiven interval are unchanged. Specific weekdays and
every-N-days schedules are not here: they would change the streak rules.
