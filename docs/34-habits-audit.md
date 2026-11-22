# Habits audit (2.9.0)

The module was already careful about civil dates, one record per day and
forgiving streaks. This pass looked for the places where it still lost data,
said the wrong thing, or left a real need unmet, and changed only those.

## What was wrong

- **Unknown record fields were dropped.** Editing, archiving, unarchiving or
  changing an amount rebuilt the record from the fields this version knows, so
  anything a later version (or the platform) had written disappeared. The kit's
  rule 5 asks every module to keep them.
- **Legacy weekly records could read as daily.** A record written before
  `schedule` existed used `weekly: true`; `Habit.fromBody` ignored it.
- **A reminder named the wrong progress.** `habitArmReminder` measured the
  habit at the future alarm instant, so an amount habit's notification always
  said «0 of 8» instead of today's count.
- **`HabitRatePanel` was never placed.** The 7/30/90-day panel existed but no
  screen showed it.
- **Many habits broke the day ring.** The gap between arcs was computed from
  the stroke width alone; past a dozen habits it exceeded each arc's span and
  arcs drew inside out.
- **The Today list walked the history twice per habit per build.** It computed
  the logged amounts and then recomputed them inside `fromChecks`.
- **There was no way to rest.** Archiving hid a habit from Today entirely and
  lost its place; travel, illness and hard weeks are ordinary in Iran, and a
  missed week should not break a streak the person did not abandon.

## What changed

### Rest days

`Habit.pauses` holds inclusive civil-date stretches (`{"from","to"}`), at most
40, merged when they touch. The rest sheet — **Take a rest…** on a habit's page
— offers today, 3, 7, 14 or 30 days, or a chosen last day.

- A rest day is **not due and not missed**: `dueOn` is false, `dayState` is
  `off`, and `_occurrences` never walks it, so streaks, best streaks and
  consistency pass over it.
- A weekly target's week holding a rest day is left out of the streak, the best
  streak and the rate, so a two-week trip neither counts nor breaks a run.
- The reminder is silent during a rest and lands on the first day after it; the
  search horizon grew to 400 days so a year-long rest still keeps its alarm.
- Today shows resting habits in their own visible **Rest days** section (not in
  the folded «Not today» list), with the day the rest ends.
- Ending a rest that began today removes it; ending an earlier one stops it
  yesterday, so today is a habit day again.
- A check-in made during a rest still counts — the person is allowed to do the
  thing they are resting from.

### Everyday Iranian ideas

The editor's ideas now open with the five daily prayers (an amount of 5), a few
pages of the Quran (3) and a weekly charity, before water, reading, walking,
exercise, language, sleep, screen time, tidying and journaling. Names and units
come from the module's own strings in both languages.

### Fixes and polish

- `Habit.extra` / `HabitCheck.extra` keep unknown fields and write them back on
  edit, archive, pause, undo and amount changes; a check-in's original `at` is
  kept when its amount changes.
- Legacy `weekly: true` records open as weekly again.
- Reminder text measures today, not the alarm day.
- The rate panel (7/30/90 days, 12 finished weeks) is on the habit page, with
  amounts passed so a part-filled day is not read as done.
- The day ring clamps its gaps to a third of each arc, so every habit draws.
- Today's standings are computed in one pass per habit.

## Checks

Run from `apps/client` with the repository's toolchain:

```text
flutter analyze --no-pub --fatal-infos          # clean
flutter test --no-pub test/modules/habits       # 152 tests, all green
flutter test --no-pub test/module_kit_test.dart test/module_shared_rules_test.dart
flutter test --no-pub test/module_glance_test.dart test/app_guide_test.dart
flutter test --no-pub test/whats_new_test.dart test/update_sheet_test.dart test/version_test.dart
```

New tests: `habit_pause_test.dart` (stretch merging and ending, malformed
records, streak and rate neutrality, weekly rest weeks, reminder horizon,
unknown fields, legacy weekly) and `habits_pause_widget_test.dart` (taking a
rest from the menu, seeing it on Today, ending it, an edit keeping an unknown
field, the Persian ideas).

## Remaining

- Rest stretches can be started and ended, but past stretches are not edited in
  the UI (the record is plain JSON and keeps them).
- A rest day inside a weekly target neutralises the whole week rather than
  reducing that week's target.
- Notification delivery, TalkBack and large text were checked in widget tests
  and the screen-review harness, not on a physical device.
- Per-day notes and sharing a progress summary are still open ideas, not built.
