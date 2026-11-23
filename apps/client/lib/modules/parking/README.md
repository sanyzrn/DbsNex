# Parking

## Audit (upgrade pass)

Parking has been available since 2.8.4. Records from every earlier build still
open and save as they were; the upgrade kept every kind, the storage, recovery,
drafts and Undo, and changed what the brief asked for. A second audit (2.8.18)
is recorded in [`docs/36-parking-audit.md`](../../../../docs/36-parking-audit.md).

What the module did before, screen by screen:

- **Main screen** — a hero line, the open parking(s) as a card with place,
  floor, spot, elapsed time and a small "ends in", remembered places, recent
  search, closed history with delete and Undo, one floating button that opened
  a full editor whose only required field was the place.
- **Editor** (sheet) — place first, everything else behind "More details":
  vehicle, floor, spot, landmark, typed coordinates, paid-until date/time,
  Save and Keep draft & close.
- **One parking** (page) — every field, dates, duration, share, edit, delete,
  Found my car, and the opt-in device reminder.
- **Reminder** — the platform's free-time control: pick a date and a time.
- **Dialogs** — earlier parking for the same vehicle, discard, delete, clear
  history, each with the platform banner and Undo.

What was below the brief and is now fixed:

| Brief ask | Before | Now |
| --- | --- | --- |
| "I parked" in one tap | The floating button opened a sheet; saving took at least two taps and typing | `I parked` writes an open parking immediately: the vehicle from the last parking, everything else empty. `Park with details` and the card's add-where action still open the full editor |
| Floor, spot and clue optional — everything optional | The place was required, so a hurried person could not save at all | A place is optional; the card offers `Add where it is`, and a place-less parking shows as "Parking" |
| Paid until, time left shown large | A small `Ends in …` line | The remaining time is the large line on the card, with `Left on the meter` (or `Past the paid time`) under it |
| A reminder some minutes before, default 10, editable | Only the platform's free date-and-time picker | A paid parking offers `Remind me before it ends`: a sheet with 5/10/15/30 chips and a minutes field, ten by default, ringing that many minutes before the written end; a parking without paid time keeps the free-time control |
| "I'm back" | `Found my car` | `I'm back`, same one tap, same history, same reminder cleanup |
| Favourite places (home, work, the usual mall) to fill in one tap | Recent places only, in save order | A star on every remembered place; favourites get their own heading above the rest, and tapping one still fills the editor in one tap |
| One-handed and fast | Place first, required, and the primary action led to a long form | The thumb-sized `I parked` button is the primary action; the long form is optional and reachable from the app bar, the empty state and a card |
| No location, no camera, no fetching | Already true | Still true: coordinates are typed, no map SDK, no network, no photo |

### Audit 2.8.18 — what real use exposed

- **The star survived the next visit.** `rememberPlace` rebuilt a place with
  `favourite: false` and merged it over the old body, so every return to a
  favourite un-starred it. The rebuilt body now carries the existing mark.
- **A reminder reopened on the lead it was given.** The quick sheet always
  started its field at `10`, so opening a 30-minute reminder and saving changed
  it to 10. It now opens on the saved minutes (or a lead that fits a short
  stay); chips that cannot fit are disabled.
- **Closing an earlier car cleared its alarm.** `save(closeEarlier: true)`
  wrote `foundAt` but left the earlier reminder key behind. It is cleared after
  the group commits, best-effort like «I'm back».
- **One tap used the car parked most recently.** The old code took the first
  non-empty vehicle in store order, which is *saved* order; correcting an old
  record could make the next «I parked» use the wrong car. `lastVehicle`
  compares `startedAt`.
- **Persian and Arabic spellings meet.** Vehicle identity, place identity,
  search and query de-duplication fold yeh/kaf, Arabic-Indic digits, half-spaces
  and whitespace through `ParkingModels.fold`.
- **Search keeps an open car open.** Active matches stay as cards; only closed
  matches become history, and “nothing matches” considers both lists.
- **Under a minute is in words.** A countdown of 40 seconds no longer reads
  “0 min” on the card, history, detail or glance.
- **A reminder is not offered when it cannot fit.** Once the end is under a
  minute away, the control is gone rather than failing after a save. The same
  applies after the paid time has ended.
- **Keep it open now says so.** The conflict answer still leaves the earlier
  parking open and writes nothing new, but a banner explains that the new one
  was not saved instead of returning in silence.
- **Every place is reachable.** Six per shelf, ordered by `lastUsedAt`, with an
  **All places** sheet that can star, forget with Undo, or fill the editor.
  Rows show the landmark and use count; the star's tooltip changes when set.

Not done, and why:

- **The shared `duesBetween` and `summarize`** were left for the
  maintainers, who could edit the central pending lists; added in the
  review below.
- **A "where's my car" home-screen card** is described as Later in the brief
  and deliberately not built (see Open questions).
- **A photo of the spot and GPS** stay out of reach (Platform requests).

## Maintainer review (2.8.4)

Checked against the brief, `docs/18` and the design rules; merged with these
changes:

- **The reminder follows the paid time.** The minutes it rings before the
  end are kept on the parking (`remindMinutes`), so an edit that moves the
  end moves the reminder (`ParkingAlarm.follow`), and one that leaves no room
  for it, or removes the paid time, takes it back. Before, the alarm kept
  ringing at the old end.
- **The reminder says what it is.** Its title was the Cycle module's generic
  "Nex reminder"; it is "Parking: 10 min left" now, the place in its body.
- **What is set shows.** The card's button reads "Reminder 10 min before the
  end" once one is set, and Clear appears only then.
- **`duesBetween` and `summarize`** added (parking_shared.dart), and parking
  taken off the central pending lists.

## What it does

A manual memory of where each vehicle is parked, built for a car park and a
hurried thumb. One tap on **I parked** starts a parking; the place, floor,
spot, landmark and paid-until time are all optional and can be added from the
card at any moment. While the paid time runs, the remaining minutes are the
largest thing on the card; the same parking can carry an explicit device
reminder a few minutes before it ends. **I'm back** closes it and keeps it in
a short history with Undo. Remembered places fill the editor in one tap and
the ones marked with a star sit in their own **Favourites** row. Everything is
typed by the person: no GPS, no map, no camera, no network.

Screens:

- **Where I parked** — hero line, open parking cards, favourites, other
  remembered places, search with recent queries, closed history, an **All
  places** entry, and the one floating action.
- **Parking editor** (sheet) — place first, the rest behind More details,
  typed coordinates, paid-until date/time on the shared calendar, Save,
  Keep draft & close. Nothing in it is required.
- **One parking** (page) — every field as written, started/found/duration,
  the paid-until with its reminder, share, edit and delete.
- **Reminder before the end** (sheet) — minutes before the paid time ends,
  with 5/10/15/30 and an editable number; opens on the saved lead, offers only
  leads that still fit, and refuses a moment in the past.
- **All places** (sheet) — every remembered place, recently used first, with
  star, tap-to-fill and forget-with-Undo.
- **Dialogs** — earlier parking for the same vehicle, discard, delete and
  clear history; deletes and clearing use the app banner with Undo.

## Records

All records stay in this module's own store and follow its backup and
delete-data policy.

- **session v1** — `vehicle`, `place`, `floor`, `spot`, `landmark`,
  `startedAt`; optional `foundAt`, `expiresAt`, `lat`, `lng`, and
  `remindMinutes` (2.8.4: the minutes before the end a reminder rings). Instants are
  UTC ISO strings; legacy timestamps without an offset keep the old local
  reading. `place` may now be empty (added by this upgrade it was always
  allowed to be absent on old records). Unknown fields are preserved on edit
  and Undo.
- **place v1** — `place`, `floor`, `spot`, `landmark`, bounded `useCount`,
  UTC `lastUsedAt`, optional validated coordinates, and **`favorite`**
  (added: a boolean, missing on old records and read as false). Unknown
  fields are kept, so marking a favourite never drops anything.
- **search v1** — `query`, `at`, letter/number-folded de-duplication
  (`ParkingModels.fold`: case, Arabic/Persian yeh and kaf, Arabic-Indic digits,
  half-spaces), stored cap eight.
- **draft v1** — the raw editor fields, a base fingerprint and a stable
  target id, including a new parking's initial `startedAt`. Kept drafts
  resume; failed reads block replacement; stale drafts do not apply.
- **operation v1** — the before-image journal for a local write group; an
  uncommitted group rolls back on the next read.

## Decisions

- **One tap means one record, not a half-saved one.** `I parked` writes a
  complete session with the vehicle parked most recently (by `startedAt`, not
  by save order) and today's start. It does not
  guess a place: a wrong place remembered silently is worse than an empty one,
  and the card asks for it in one more tap only if the person has time.
- **Everything is optional, including the place.** The brief says so, and a
  hurried parker with a dead phone battery is exactly who this module is for.
- **One open parking per vehicle still holds.** A second one-tap parking for
  a vehicle that is still open asks the same question as before (close the
  earlier one, or keep it); answering Keep leaves the new one unmatched and
  unsaved rather than closing anything in silence.
- **The countdown is the glance.** Remaining time is read while the screen is
  visible, never as a background job; the exact end moment counts as past.
  A person who wants to be told after closing the app sets the reminder.
- **The reminder counts back from the written end.** Ten minutes before by
  default, editable; the same store reminder call as the platform control, so
  permission checks and auto-cancel apply. It refuses a moment in the past and
  says so. Docs/18's lead-time set is day-scale; the brief asks for minutes
  around a meter, so this is the one deliberate, documented difference.
- **Favourites are shortcuts, not automation.** A star only sorts a place
  into its own heading and marks the row; tapping it fills the editor, exactly
  as any remembered place does. It never parks by itself.
- **Search, history, drafts, recovery and Undo keep their rules**, including
  history ordered by when a parking began, not when it was saved. Search now
  folds Persian/Arabic spellings and keeps an open car as an open card; it
  still covers sessions, not the places sheet.
- **A remembered place belongs to the person, not the visit.** Parking there
  again updates its use count, landmark and last-used time without changing its
  star. Forgetting it is deliberate (All places), confirmed, and undoable;
  past sessions keep their own copy of the place text.
- **No location, camera, map link generation beyond a typed coordinate pair,
  or network.** Coordinates are validated by range, never rounded into place.

## Research

The first pass already settled the product side: people remember a car park by
floor, pillar, colour and a landmark, not by an address; the useful glance is
"how long have I got"; and the phone is in one hand with the door still open.
This upgrade leaned on three further observations, checked 2026-11-17:

- Parking apps that people keep using open on the *current* state, with the
  capture action reachable without a form; the ones people delete ask for a
  location permission before they have shown any value.
- A countdown that is one of several equal lines is not read; size and one
  caption are what make it glanceable. The card therefore gives the remaining
  minutes the headline and demotes the explanation to a caption.
- "Where I usually park" is a short list, not a history: people name home,
  work and one mall. A star (rather than another settings screen) is the
  smallest honest way to build that list from places the module already knows.

No new dependency, SDK or service was needed; all validation and arithmetic is
local, and no permission beyond the opt-in notification is requested.

## Shared across modules

- **Dates falling due (`duesBetween`)** — `ParkingShared.duesBetween`
  (parking_shared.dart): each parking's paid-until, done once it is closed.
- **Money** — none; the module stores no amounts.
- **People** — none; a parking names a vehicle, not a person.
- **A line per record (`summarize`)** — `ParkingShared.summarize`: a
  parking by its place (or vehicle) with floor, spot and landmark, a
  remembered place by its name; drafts, searches and journals give none.
- **Unknown fields** — kept: edits merge onto the raw record, and the
  favourite write spreads the old body.
- **Saving, leaving a form, Undo** — the existing draft/checkpoint flow and
  the app banner with Undo are unchanged.
- **Reminders** — set through the store's `setReminder`, with the
  platform control still offered when no paid time exists. The body names the
  place. Minutes-before is the documented difference from the day-scale lead
  times.
- **Sharing and hiding** — text only through `nexModuleShareText`; no totals
  or health data to hide. Image sharing and photos are requested.
- **Look and movement** — `NexModuleHero`, `nexShowSheet`, `NexPageRoute`,
  `NexSpacing`/`NexRadius`, `heroTag: null`, ADR-037 direction on every typed
  field; checked in Persian and English, light and dark, scale 2.0.

## Guide

**English:** When you leave the car, tap **I parked** — that is enough. If you
have a moment, tap **Park with details**, or the add-where action on the card,
and write the place, floor, pillar or a clue; a remembered place fills all of
it in one tap, and a star keeps your usual places under **Favourites**. **All
places** reaches the ones the shelves do not show and can forget an old one
with Undo. If the parking is paid, add the paid-until date and time; the card
then shows the time left in large type (in words under a minute), and
**Remind me before it ends** rings ten minutes before (change it to 5, 15, 30
or any number of minutes; a short stay opens on a lead that fits). When you
come back, tap **I'm back**: the parking moves to history, where it can be
edited, deleted and brought back with Undo. Nothing is found by GPS: you type
where the car is.

**فارسی:** وقتی از ماشین پیاده می‌شوید، **«پارک کردم»** را بزنید؛ همین کافی
است. اگر وقت داشتید، **«پارک با جزئیات»** یا دکمهٔ «بنویسید کجاست» روی کارت را
بزنید و آدرس، طبقه، ستون یا یک نشانه را بنویسید؛ یک جای آشنا همه را با یک لمس
پر می‌کند و ستاره، جاهای همیشگی را زیر **«مورد علاقه»** نگه می‌دارد.
**«همهٔ جاها»** جاهایی را که در فهرست اصلی جا نمی‌شوند نشان می‌دهد و می‌شود
یک جای قدیمی را با «بازگردانی» فراموش کرد. اگر پارکینگ پرداختی است، تاریخ و
ساعت پایان را بنویسید تا کارت زمان مانده را درشت نشان دهد (کمتر از یک دقیقه
با حرف)؛ **«پیش از پایان یادآوری کن»** ده دقیقه قبل خبر می‌دهد (۵، ۱۵، ۳۰ یا
هر تعداد دقیقهٔ دیگر؛ برای پارک کوتاه، عددی که جا شود). وقتی برگشتید
**«برگشتم»** را بزنید تا پارک به تاریخچه برود؛ همان‌جا می‌شود ویرایش کرد، حذف
کرد و با «بازگردانی» برگرداند. هیچ چیزی با موقعیت‌یابی پیدا نمی‌شود؛ جا را
خودتان می‌نویسید.

## Changelog

2.8.18 — EN: A favourite place keeps its star when you park there again; a
reminder reopens on the lead you set instead of ten; closing an earlier car
clears its alarm; one-tap parking uses the car you parked most recently;
Arabic and Persian spellings find each other; an open car stays an open card
while searching; under a minute reads in words; and **All places** reaches
every remembered place with star, forget and Undo.

2.8.18 — FA: جای مورد علاقه بعد از پارک دوباره ستاره‌اش را نگه می‌دارد؛
یادآوری با همان تعداد دقیقهٔ قبلی باز می‌شود، نه ده؛ بستن پارک قبلی هشدارش را
هم پاک می‌کند؛ «پارک کردم» ماشینی را برمی‌دارد که آخرین بار پارک شده؛ نوشتار
فارسی و عربی هم را پیدا می‌کنند؛ پارکِ باز هنگام جست‌وجو کارت باز می‌ماند؛
کمتر از یک دقیقه با حرف نوشته می‌شود؛ و **همهٔ جاها** با ستاره، فراموش‌کردن و
بازگردانی در دسترس است.

2.8.4 — EN: Parking can now be saved in one tap, with every detail optional and
addable later; the time left on a paid parking is shown large; a reminder can
ring a chosen number of minutes before it ends (ten by default); usual places
can be starred as favourites; and coming back is the single «I'm back» action.
Old records keep opening and saving as they were.

FA: پارک کردن حالا با یک لمس انجام می‌شود و همهٔ جزئیات اختیاری‌اند و بعداً
اضافه می‌شوند؛ زمان ماندهٔ پارکینگ پرداختی درشت نشان داده می‌شود؛ یادآوری
می‌تواند چند دقیقه قبل از پایان (پیش‌فرض ده دقیقه) خبر دهد؛ جاهای همیشگی با
ستاره به «مورد علاقه» می‌روند؛ و برگشتن یک دکمهٔ «برگشتم» است. رکوردهای قبلی
همان‌طور باز و ذخیره می‌شوند.

## Platform requests

1. **Permission-gated location and a map** (the brief asks us to ask): the
   module works without them today — typed place and coordinates. A future
   version would use a fix only after an explicit tap, store it on the record
   and show a map, never read location in the background.
2. **A photo of the spot**, attached to the session and kept with backups;
   meanwhile the landmark text stands in.
3. **Minutes-scale lead times** in the shared reminder vocabulary: the
   documented set is days, but a parking meter needs 5/10/15/30 minutes.
4. **`ModuleDue` and `ModuleSummary` in the kit**, so this module's own
   definitions (parking_shared.dart) can go.
5. **Image sharing** for a spot card (text is shared today).
6. **Atomic compare-and-write / group transactions** for multi-window races;
   the local serialization, fresh reads and recovery journal are the honest
   fallback.
7. **A home-screen "where's my car" card** while a parking is active — the
   brief's Later item; it needs a platform surface outside the module.

## Device checklist

1. Open the module with an old parking and an old remembered place: both
   read as before, and the place has no star until you give it one.
2. Tap **I parked** with nothing filled: a card appears immediately, with
   `Add where it is` and **I'm back**.
3. Tap **Park with details**, write a place, floor and clue, and save: the
   card shows them; the place appears under Places you use.
4. Star that place: it moves under **Favourites**; tap it and the editor is
   filled in one tap; unstar it and it returns to the other list.
5. Add a paid-until time a couple of hours ahead: the remaining time is the
   large line and counts while the screen is open; background the app and
   return to see it refreshed.
6. Tap **Remind me before it ends**, keep 10 minutes, allow notifications:
   the alert arrives ten minutes before, names the place, and disappears if
   you tap **I'm back** first.
7. Try 5 and 30 minutes; a short paid time offers only leads that fit and the
   control disappears under a minute. The sheet itself still refuses a past
   moment with words, not silence.
8. Tap **I'm back**: the parking moves to history with its duration; delete
   it and use Undo.
9. Park the same vehicle twice without coming back: the earlier-parking
   question appears, and both answers behave as before.
10. Persian and English, light and dark, text scale 2.0, and a 320×480 phone:
    the card, the favourites row, the reminder sheet, the All places sheet and
    the editor all stay usable and the primary action reachable with a thumb.
11. Open All places, forget a stale place, and Undo: the place returns with
    its star; past parking that named it is unchanged.

## Open questions

- Should **I parked** prefill the last place as well as the last vehicle, for
  people who park in the same car park every day, at the risk of a wrong place
  when they do not?
- Should a favourite be nameable ("Home", "Work", "Mall") instead of only
  starred, and should those names be shared with other modules?
- Is a minutes-before reminder enough, or does the owner also want the
  day-scale lead times the shared reminder vocabulary describes?
- Should the "where's my car" card be built here once the platform offers a
  home-screen surface, or left to the platform?
- Should a parking with no place be allowed to stay open indefinitely without
  a nudge, or should the card ask once after a few minutes?
- When the kit gains `duesBetween` and `summarize`, should parking's paid-until
  appear on the shared calendar at all?

## Checks

Run from `apps/client` with the repository's pinned Flutter:

```text
dart format lib/modules/parking test/modules/parking
flutter analyze --fatal-infos
flutter test test/module_kit_test.dart test/module_shared_rules_test.dart test/modules/parking
flutter test
```

Results on this pass: `dart format` clean on the touched files;
`flutter analyze --fatal-infos` over the whole client — "No issues found!";
the gate with the shared rules and the module — **251 passed**, of which the
module alone is **135** (all old tests still green plus eighteen regression
tests from the 2.8.18 audit); and the full `flutter test` run reported in the
final reply. No parking file is over 400 lines.

Only `lib/modules/parking/`, `test/modules/parking/`, this README, the audit
doc, `CHANGELOG.md` and the client version changed. Parking was already in
`module_rollout.dart` (available since 2.8.4); the earlier “Soon” note here was
stale and is corrected.

Screens in `review/`: the main screen in Persian dark and English light,
including an open paid parking and a favourite place, plus the reminder sheet.
They are widget renders with synthetic data, not device screenshots. Android
and iOS notification permission, the real keyboard, TalkBack/VoiceOver and
release builds still need the owner's phone.
