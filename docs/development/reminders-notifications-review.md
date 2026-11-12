# Reminders and notifications: an audit of the whole path

Scope: `lib/platform/reminders.dart` and everything under `lib/platform/reminders/`,
`module_notification.dart`, `module_notification_route.dart`,
`services/ringing_services.dart`, the module reminder layer
(`platform/module_services.dart`, `modules/habits/habit_reminder.dart`,
`platform/cycle_reminders.dart`), the Android manifest's receivers, permissions and
services, and the tap routes in `screens/timeline_screen.dart` /
`screens/timeline/timeline_navigation.dart`.

This is the record of what was checked, what was wrong, and what was deliberately left
alone. It is not a changelog — the user-facing half is in `CHANGELOG.md`.

## Fixed

### 1. A module reminder carried the wrong day, for two different callers

`NexModuleAlarms.scheduleModule` built the payload's `day` from `at.year/month/day`, the
fields of whatever `DateTime` it was handed. Two callers hand it different ones:

- `setModuleReminder` (the picker, the habit tile, cycle) passes **local** time.
- `restoreModuleReminders` (the launch re-arm) passes the **UTC** instant it read from
  the stored record, because `at` is stored as `at.toUtc().toIso8601String()`.

So for any reminder ringing between local midnight and the zone's offset from UTC, the
restored alarm's payload named the *previous* day. That payload is what the shade's
buttons act on: `applyHabitActions` requires `dateKeyOf(day) == target.day` and writes
`HabitCheck.idFor(habit.id, target.day)` — so **Done** on a 02:00 habit reminder logged
a check on yesterday's square, or (when the habit was not due yesterday) was dropped as
"not today". The same divergence also gave the two paths different
`NexReminders.snoozeIdFor(payload)` values, so the launch sweep and the snooze that was
actually armed could disagree about the same reminder.

The day is now taken from `at.toLocal()` — one payload for one reminder, whoever arms it.
The instant handed to the platform is untouched: only the date the buttons carry changes.

Proved by `test/module_reminder_alarm_test.dart`, run under `TZ=Asia/Tehran`: with the
old code the payload said `2027-03-02` for a reminder ringing at `2027-03-03 02:00` local
(22:30 UTC). Test hosts in UTC cannot see this at all, which is why it survived.

### 2. Every reminder honoured the app lock except the module ones

`hideOnLockScreen` was consulted for notes (`noteDetails`), recurring items
(`commitmentDetails`), habit reminders (`NexHabitNotificationActions.details`) and the
daily nudge (the native receiver reads `flutter.security.app_lock` directly). The
non-habit branch of `scheduleModule` — cycle, occasions, medicine, warranty, parking,
maintenance, words, lent — hardcoded `NotificationVisibility.private` and ignored the
hook entirely.

`private` is exactly what this class documents as *not* protecting anyone: it shows the
item's words to anyone whose Android is set to show sensitive content, and the words are
the whole secret — a medication, a parking floor, an appointment. The branch now uses the
same `secret ? secret : private` as the habit branch beside it.

### 3. A module alarm could report "set" without being set

`_verify` exists for one reason, written on its own docstring: `zonedSchedule` returning
without throwing means the request was accepted, not that anything is pending. Notes and
the daily nudge ask. `scheduleModule` did not — it returned `true` after the call, and
`restoreModuleReminders` then put its id into the sweep's `wanted` set whether or not the
alarm existed.

It asks now, and reports what it found in `lastError`. The habit tile already shows its
failure banner on a `false` return, so a phone that drops exact alarms says so instead of
claiming the reminder is on. A drop stays recoverable: the alarm is rebuilt from the
library on the next launch.

### 4. A preferences failure could escape as an exception, with the alarm armed

`NexHabitNotificationActions.remember(...)` was called *outside* `scheduleModule`'s `try`,
and unlike `NexReminderActions.remember` it has no `catch` of its own. A failed write
threw out of `scheduleModule` — past its `return false` contract — while the alarm was in
fact armed, so the caller reported a crash for a reminder that works. `lastError` was also
cleared *after* the call, so a failure there would leave the previous error standing.

`lastError` is now cleared before anything that can fail, and the words for «remind later»
are kept in a `try` that costs the button, not the reminder.

### 5. Turning a module reminder off could throw

`cancelModule` read `pendingNotificationRequests()` unguarded. On a queue that would not
read, the exception left the item with its switch flipped and its alarm still armed. The
whole body is guarded now and diagnosed; the direct `cancel` for the known id still runs
first, so the ordinary case is unchanged.

## Checked and found sound

- **Permissions.** Every entry point that sets a reminder asks: the reminder picker, the
  module reminder setter (`setModuleReminder`, which every module and every habit goes
  through), the Cycle switch and the settings sheet. Exact-alarm permission is read from
  `canScheduleExactNotifications()` on every `initialise` — not cached from the last ask —
  and the jump to the system screen is gated by `shouldRequestExactAlarms` /
  `onExactAlarmsRequested` so it is shown once, explained, rather than on every reminder.
- **Reboot.** The plugin's `ScheduledNotificationReceiver`, `ActionBroadcastReceiver` and
  `ScheduledNotificationBootReceiver` are all declared (with `BOOT_COMPLETED`,
  `MY_PACKAGE_REPLACED`, `QUICKBOOT_POWERON`), and `NexDailyNudgeReceiver` re-arms itself
  on boot, on its own time zone change and after an app update.
- **Cold and warm taps.** All four launch cases are read once and cleared once
  (`takeLaunchNoteId`, `takeLaunchModule`, `takeLaunchedFromRecurring`,
  `takeLaunchedFromUpdate`), and each is consumed in exactly one place. A "Log progress"
  button that launched the app arrives as `_launchModule` with `forProgress()`, matching
  the warm path. The timeline sets `onOpenModule` before taking the launch module, so a
  late `initialise` cannot deliver the same tap twice — and cannot lose it either,
  because the two synchronous steps cannot interleave.
- **The app lock's holds.** `_arrivalHeld`, `_moduleArrivalHeld`, `_recurringArrivalHeld`
  keep a tap from opening a screen behind the gate, and `_resumeHeldArrival` replays them
  after the unlock.
- **The prune.** `syncFromLibrary` spares the reserved block, Cycle's keys, every snooze
  id and the module ids `restoreModuleReminders` returns; module alarms are rebuilt from
  the `__reminder` records on every launch, and a module that is switched off has its
  alarms swept.
- **The id space.** `idFor` bumps out of `reservedIds` (0 nudge, 1–2 diagnostics,
  3 download) and `unreserved` is the one place that number is applied.
- **Repeats.** A daily module alarm is scheduled once with `DateTimeComponents.time` from
  the next local wall-clock occurrence (`nexNextDailyRing`), a note repeat is advanced by
  arithmetic rather than a walk, and `_withdraw` — not `cancel` — is what re-arming uses,
  so a notification already in the shade stays there (2.1.9).
- **The shade's buttons.** **Done** and **In an hour** work in a background isolate that
  has no database: what they need (the words, the language, the note id) is in
  preferences, the habit queue is keyed per habit/day so a repeated tap is idempotent,
  and a queued habit action that cannot be written stays queued.

### 6. One acknowledgement, two readers, and a launch race

`ringing_services.syncRinging` drained `reminders.acked`, and
`daily_nudge_services` read the same key while planning the nudge. Both run at launch:
the timeline wires `_wireRinging` in `initState`, and the nudge is planned shortly after
the service graph exists. Whichever ran first consumed the list, so a **Done** pressed
before the app opened could be drained by the sweep and then planned against by the
nudge as if it had never happened — one mention of a reminder that was already answered.

The list was never the fact; it is the only thing a button handled in a background
isolate (no database) can leave behind. There is now one reader,
`NexRingingServices.settleReminderAcks`, and it writes the answer where the note lives:
`notes.reminder_acked_at`, read as `Note.reminderAckedAt`. The nudge plans against that
column, so the order of the launch sweep and the plan no longer matters. A **Done**
delivered while the app is in front writes the same column directly.

The answer is deliberately *not* a reason to clear the note's `dueAt`. That is a product
decision about what **Done** means for a one-off reminder, and this change does not make
it silently: the reminder stays, a repeating one comes back at its own time, and a
future time is untouched. The daily plan leaves out only the due line for the day it was
answered (`Note.reminderAnsweredOn`); later days still carry it. Setting a new time
clears the acknowledgement, since that is a new request rather than an answer to the old
one.

Proved by `apps/client/test/daily_nudge_coordinator_test.dart` in both launch orders,
and by the day/repeat case in `daily_nudge_content_test.dart`.

## Known, and deliberately left alone

**A download-progress tap opens the app, not the update screen.** `showDownloadProgress`
posts id 3 with no payload; only the "ready" entry carries `nex:update`. Left as is: the
transfer is deliberately dismissable and the ready notice is the one with something to do.
