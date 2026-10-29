# Birthdays & occasions (`occasions`)

## What it does

A list of dates that matter — birthdays, anniversaries, remembrances, anything
else — each kept **in the calendar it is celebrated in**. A Jalali date comes
back on the same Jalali day every year (its Gregorian date moves by a day from
year to year); a Gregorian date comes back on its Gregorian day. The list
groups what falls today, in the next 7 days, in the next 30 days and later,
nearest first; each row shows the next day in the occasion's own calendar, the
age or year it comes to (only when a start year was given) and how far away it
is. An occasion opens to a page with the countdown, the day in both calendars,
a greeting to copy or share, and its note.

29 February and 30 Esfand do not exist every year. The person chooses, once, to
use the last day of that month or the first day of the next; nothing is rolled
over by accident.

A start year is optional («I do not know the year»): without it no age is shown
and none is guessed.

Not here: reading contacts or a calendar, importing, sending anything to
anyone, photos, widgets, CSV/ICS export. They need platform interfaces the
module kit does not give (see Platform requests).

## Records

- `occasion` v1: `title`, `kind` (`birthday`, `anniversary`, `memorial`,
  `other`), `calendar` (`jalali`, `gregorian`), `month`, `day`, `yearKnown`,
  `year` (in that calendar; absent when unknown), `leapPolicy` (`lastDay`,
  `nextDay`), `note`, `favorite`, `muted`, `archived`, `remindDays` (days
  before, 0–30; absent for no reminder), `remindMinutes` (minutes after
  midnight), `createdAt`. A date is stored as calendar + year/month/day, never
  as a Gregorian timestamp, which would drift for a Jalali date. An unknown
  kind reads as `other`, an unknown calendar as Gregorian; a record with an
  impossible month or day stays in the store, is listed under «Needs a date»
  and is never given a guessed date. Editing writes over the record but keeps
  fields this version does not know.
- `draft` v1, `occasion:new` / `occasion:<id>`: what was typed in the sheet,
  kept if the sheet is swiped away, removed on save or cancel.
- `__reminder` (the kit's): the alarms below.

## Decisions

- **Reminders (2.4.0).** A platform reminder is a one-time alarm, and a
  module has no honest yearly one. So the alarms for the next two times the
  date falls are kept ahead: on the day itself (`occ:<id>:c`, `:d`), and, when
  a day ahead was chosen, that many days before too (`occ:<id>:a`, `:b`).
  They are made again whenever Nex starts or comes back to the front — the
  module's `keepUp`, which the app calls for every module that is on — as
  well as when the module opens and when the occasion is saved, so a date
  keeps ringing year after year without its screen being opened. A new date
  reminds by default (a day before and on the day, at 09:00). They are
  cleared when the occasion is deleted, archived or muted. The notification
  is the occasion's name with its mark (🎂, 💞, 📅) and when it is, with the
  age it comes to — except a remembrance, which stays neutral on a lock
  screen. They need the notification permission; when an alarm cannot be
  set, saving still succeeds and the person is told once.
- **Not tied into the timeline.** A date is not copied into the notes, the
  brief or the assistant: remembrances are personal, the module kit keeps a
  module's records to itself, and the reminders already reach the person at
  the moment it matters.
- **The look (2.4.0).** The nearest date leads the page in a card in its
  kind's colours (warm for a birthday, rose for an anniversary, dusk for a
  remembrance, violet otherwise) with a countdown ring, and, on the day,
  copy and share buttons for a greeting. Each row is a calendar page with
  the day in the occasion's own calendar, and a pill for how far away it is.
  Each kind has three greetings, with **Another** to switch between them.
- **The Jalali code** is the app's own (`nexPersianDate`, `nexGregorianDate`,
  years 1–3177); outside it, an occasion has no next day and is listed to be
  fixed rather than guessed.
- **Greetings** are plain text a person copies or shares by their own tap.

## Words, guide, changelog

Both languages are in `module.dart`. Guide: the Modules paragraph lists
Birthdays & occasions. Changelog: «Birthdays & occasions: Jalali and
Gregorian dates that repeat in their own calendar, countdown, greeting and an
optional reminder.»

## Platform requests

- Contacts and calendar import, with preview.
- A yearly (or rolling) reminder, so no renewal on opening is needed.
- Export (CSV/ICS) and a home-screen widget.
