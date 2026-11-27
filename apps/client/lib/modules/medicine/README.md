# Medicine

## Audit (module-medicine-audit)

A pass over the finished module, fixing what had drifted and sharpening
what a household reads first. Nothing was renamed, no record changed
shape, and every inherited test still passes.

**Fixed:**

- **The Today card counted answered doses as open.** It said "3 doses
  today" all day whatever was logged, because it never read the dose
  logs. It now counts the moments still open, and when a day is fully
  logged it says so ("All of today’s doses are logged") instead of
  counting zero.
- **A dose logged from the detail sheet never answered its routine
  moment** — not on the Today card, not in the quick view, not on the
  home screen’s dates, which read "0 of N doses today" for a person who
  logs from the sheet and never opens Today. A log now answers the
  moment named by its slot, or its own clock time if no slot is present;
  one log cannot answer two moments. A log whose action is neither taken nor
  skipped answers nothing.
- **The Persian reader saw English** for "No medicine for this person
  yet" — the Persian map carried the English sentence.
- **The duplicate-name question showed "Delete it?"** — it reused the
  delete dialog’s words for a question that is not about deleting. It
  now says what the choice is.

**Added:**

- **"Me" in the person filter.** The README promised it; the chips never
  had it, so a mixed household could not see only the person’s own
  medicines. It appears beside the names when the list mixes "me" with
  named people.
- **The next dose on each row** ("Next at 21:00"), and "All of today’s
  doses are logged" when a medicine’s day is done — the cabinet is the
  home screen, and where today stands is the first thing it is opened
  for. A moment with everything in the past and nothing ahead says
  nothing rather than inventing a "next".
- **A "Next" heading on the Today page** for the first open moment still
  ahead, so a full list does not have to be scanned to find it.
- **A note when a routine names both day rules.** Weekdays win over
  "every N days" (a rule the record always had); the editor and the
  detail sheet now say so instead of leaving both looking alive.

**Kept quiet on purpose:** only the row whose write is in flight waits
on the Today page (the whole page used to lock); the page rereads the
day when the app comes back to the front, so one left open overnight
stops saying "today" about yesterday; the detail sheet builds the
newest fourteen history rows first and the rest on request — a routine
kept for months used to build every row on open; and the summary cards
open their page from anywhere on the card, not only from the button.

## Audit (upgrade pass)

The module already did these, and they are kept exactly as they were: names,
strength/package, instructions, reference times/days, private notes, optional
quantity and dose units, expiry and refill threshold, explicit Taken/Skipped
logs with a real stock deduction, correction/Undo, archive with history,
durable drafts, journaled record groups, the shared Jalali date entry, the
one-time reminder control, FA/EN and the honest "this is not medical advice"
line. Nothing that was here was renamed, removed or rewritten in meaning.

What the brief asked for and the module did not have, now done:

| Brief item | Before | Now |
| --- | --- | --- |
| Whose medicine it is, me by default | none | `person` on the medicine (free text, '' = me); a person chip on each row, filter chips above the cabinet, and the person named in the reminder |
| Times per day, weekdays or every N days, start/end | free-text times + free-text days | `times` plus `weekdays` (Mon…Sun), `everyDays` with the day it started, `startsOn`/`endsOn` civil days; the detail sheet prints the routine it reads |
| Reminder naming medicine and person, after restart/Doze/app closed | one explicit one-time alert | the routine is planned into concrete OS alarms (`NexModuleStore.setReminder`) for the next 7 days, at most 8 per medicine, each titled with the medicine and worded with the person and time; alarms that no longer match are withdrawn on every open |
| One-tap Taken / Skipped | only on the detail sheet | Today page: each routine moment has Taken/Skipped in one tap, logs carry the `slot` they answer, and stock moves exactly as before |
| "Runs out in about N days" + editable early warning (default 10) | only a refill threshold | quantity ÷ units a day from the person's own routine (weekly counted over the week), plus a per-medicine warning in days, default 10; shown on the detail sheet and as a cabinet card |
| Boxes, each with expiry, expiring/expired list | one expiry per medicine | `box` records (expiry day, optional units); an expiry page with expired and expiring groups; the legacy medicine expiry stays visible and is listed too |
| Per-medicine place / price / date log | none | `source` records: where, how much in tomans (stored as whole rials), the day; added from the detail sheet, deleted with Undo |
| `NexSecureWindow` offer | none | a settings record offers "hide this screen in the app switcher"; acquired while the screen is mounted and released on leave; nothing is claimed about encryption |
| Jalali dates, tomans, calm "hard to find lately" note the person sets | Jalali dates only | Jalaali labels everywhere (expiry, box days, places, today), toman entry/display for prices, and a person-owned switch that only prints their own note — never a judgement about supply |
| Do not advise doses/interactions/substitutes, never fetch, never name pharmacies | held | still held: the editor asks for the person's own numbers and words, the runout text is arithmetic over those numbers, the place field is free text with no list, and there is no network code |

Not done, deliberately: counting boxes into stock (boxes stay informational, so
the one quantity a taken dose moves is never silently rewritten); photos or
barcode scans (platform request); any automatic "you missed a dose" claim (the
module only shows a moment as "no record"); naming a pharmacy from a list.

Audit of the plumbing the upgrade touched: sheets go through `nexShowSheet`
(no bare dialogs, no `showModalBottomSheet` in module code), the cabinet's FAB
still carries `heroTag: null` inside the shell hero, money follows the
whole-rial/toman-display rule the borrowed/lent module already uses, and the
editor's Save sits below the scrolling form because the longer form otherwise
pushed it out of reach at 320×480 with 2× text.

## Maintainer review (2.8.4)

Merged after checking the brief, `docs/18` and the design rules; changed:

- **Reminders no longer wait for the cabinet to be opened.** They were
  planned only on opening it, for at most eight moments a medicine — under
  three days of a three-times-a-day routine — so whoever did not open the
  module stopped being reminded. Now Nex keeps them ahead on every start and
  return (`MedicineModule.keepUp`); an every-day routine uses the
  platform's repeating daily reminder, which never runs out; other routines
  are planned a full week ahead.
- **The person is `{"name": …}`** (docs/18, rule 3), as every module gives
  the other party; "me" is no `person` at all. The plain string this
  upgrade first wrote still reads.
- **A place's price is `priceRial`** (rule 2); `price` still reads.
- **`duesBetween` and `summarize`** (`medicine_shared.dart`): each moment a
  routine names, done once a log answers it, and each box's expiry; a line
  per medicine with whose it is — all private. The module left the central
  pending lists.

## What it does

The cabinet is the home screen: a quiet hero with the count, a person
filter ("me" included when the list mixes people), a Today card (how many
routine moments are still open, and "all logged" when none are), an expiry
card (how many days need a look), then one row per medicine — name, strength,
whose it is, stock, the next dose still ahead, the earliest expiry and a
"hard to find" mark the person set.

Pushing Today lists every routine moment for today with Taken and Skipped,
the first one still ahead under a "Next" heading. A moment logged from there
keeps the time it answers (`slot`) and moves stock only when the medicine has
both a quantity and a dose unit count. Yesterday's
unlogged moments appear under "yesterday, no record" — the module never calls
them missed. A log can be corrected; Undo is guarded against later changes.
The page rereads the day when the app returns to the front.

Pushing Expiry lists expired and soon-expiring boxes (and legacy medicine
expiries), grouped, with a delete that can be undone.

The detail sheet holds the person's information, the routine, the forecast
("runs out in about N days"), the warning, their hard-to-find switch, the
reminder block, Boxes (add/delete) and Places (add/delete); the dose history
opens on its newest slice, with the rest one tap away. The editor holds
the person, weekday chips, "every N days" with a start day, the start/end
dates, the warning, and the hard-to-find switch, along with everything that
was already there. No dose, interaction or substitute is ever suggested, and
nothing is fetched.

## Records

- medicine v1/v2 readable; saved form v3: `name`, `strength`, `package`,
  `instructions`, `times`, `days`, `purpose`, `archived`, optional `quantity`,
  `doseUnits`, `expiresAt`, `refillThreshold`, and the upgrade's `person` (`{"name": …}`, absent for me),
  `weekdays` (1 = Monday … 7 = Sunday), `everyDays` (2…366), `startsOn`,
  `endsOn` (civil `yyyy-MM-dd`), `warnDays`, `hardToFind`. A record written
  before the upgrade simply lacks the new keys and reads as: me, every day, no
  dates, warning 10. Unknown keys are preserved on text-only edits.
- dose v1 readable; v2 as before; the upgrade adds optional `slot` (`HH:mm`,
  the routine moment a log answers). No dose field was renamed.
- box v1: `medicineId`, `expiresAt` (civil day), optional `units`, `addedAt`
  (UTC stamp). Boxes never sum into `quantity`.
- source v1: `medicineId`, `place`, optional `priceRial` (whole rials;
  `price` from before the review still reads), `at`
  (civil day it was bought/looked).
- settings v1, a single record with id `settings`: `secure` (bool). Absent =
  off. It is an ordinary record, so backup and remove-data cover it.
- draft v1 and operation v1 unchanged. Deleting a medicine also removes its
  boxes, places, logs and draft inside the same journaled group, so Undo
  restores the whole thing.

All records follow Nex module backup/remove-data behavior. The module does not
claim encryption; the secure window only hides the screen where the platform
API provides it.

## Decisions

**People are a name, not an account.** `person` is text the person typed; ''
means "me". There is no contacts permission, no household record to keep in
sync and no way to leak a name to another module. Filter chips are built from
the names actually present, "me" included.

**The routine is the person's, not a prescription.** Weekdays and "every N
days" are alternatives read by one schedule object; when a record carries
both, the weekday set wins because it is the more specific thing the person
did. `everyDays` counts from `scheduleFrom`, which is written the first time
the rule is used so the cycle never drifts with later edits. `startsOn` and
`endsOn` bound the days the rule may name.

**The forecast is arithmetic and says so.** `runsOutInDays` = quantity ÷
(units per dose × moments per day), with a weekly routine counted over the
seven days it covers. It returns null unless quantity, dose units and at least
one time exist, so the module never invents a number. The warning is the
person's own `warnDays` (default 10) and the mark appears when the estimate is
at or under it. No clinical claim is attached to either.

**Reminders are planned alarms, kept ahead by Nex itself (2.8.4).** The plan
is rebuilt when Nex starts and each time it comes back (`keepUp`), and when
the cabinet is opened. A routine every day with no end rings through the
platform's daily reminder, one per time (`med-<id>-dHHmm`), which keeps
ringing however long the app stays closed; any other routine is planned as
its concrete moments over the next eight days, up to 32 per medicine and 160
for the cabinet (`med-<id>-<yyyyMMddHHmm>`). Titles are the medicine's own
name; bodies name the person and the time. Alarms that no longer match are
withdrawn. If the platform refuses one, the plan stops quietly rather than
retrying in a loop.

**Today never accuses anyone.** A moment is "no record", not "missed". Only the
person's own tap writes a log. Stock leaves only through the same
`MedicineRepository` path the detail sheet uses, so correction and Undo behave
identically wherever the log came from. A log answers the moment it names
(`slot`) or, when no slot is present, the moment at its own clock time;
this one match is what the Today page, the Today card, the quick view and the
home screen's dates all read.

**Money.** Prices are whole rials inside the record (`price`), entered and read
as tomans — the unit people quote — with grouping and Persian digits. The
parser accepts Persian/Arabic digits and separators, rejects negatives,
fractions of a rial and values beyond 2^53−1; an empty field is simply "no
price recorded". Nothing is fetched and no pharmacy list is built.

**Privacy.** The secure switch is off until the person turns it on, is stored
in an ordinary record so backups keep the choice, and only calls
`NexSecureWindow.acquirePrivateSurface` while the cabinet is mounted. Leaving
the module releases it. The module makes no stronger promise than the platform
API does.

## Research

Nothing external was fetched for this pass and the module contains no network
code. The decisions above come from the repo's own conventions: `docs/16`
(record/version discipline), `docs/17` (module API and rollout), `docs/18`
(product rules), the shared date label and calendar entry from the module API,
and the borrowed/lent module's whole-rial storage with toman display, which
this module copies rather than inventing a second money convention. The brief's
"hard to find lately" wording was implemented as a person-owned note precisely
because stock or supply claims are not something this module can know.

## Guide

EN: Add the medicine with the name and details exactly as you wrote them, and
say whose it is. Set the times you actually take it and either the days of the
week or "every N days" with a start day. If you count your stock, add how many
units you have and how many one dose uses — the cabinet will then say about how
many days it lasts, and warn you earlier if you raise the warning days. Each
box can have its own expiry; the Expiry page gathers the expired and the
soon-expiring ones. Where you found it and what it cost can be logged in
tomans, with the day. Today lists today's moments so one tap records Taken or
Skipped; nothing is ever marked missed for you. The "hard to find lately"
switch only prints your own note.

FA: دارو را با همان نام و جزئیاتی که خودتان می‌دانید ثبت کنید و بگویید مال
چه کسی است. ساعت‌هایی که واقعاً مصرف می‌شود و یا روزهای هفته یا «هر چند روز
یک‌بار» را با روز شروع بنویسید. اگر موجودی را می‌شمارید، تعداد واحدها و
مقدار هر نوبت را وارد کنید تا برنامه بگوید حدوداً چند روز دوام می‌آورد و
زودتر هشدار بدهد. هر جعبه تاریخ انقضای خودش را دارد و صفحهٔ انقضا، گذشته‌ها
و نزدیک‌شده‌ها را یک‌جا نشان می‌دهد. جای خرید و قیمت به تومان با تاریخ ثبت
می‌شود. صفحهٔ امروز نوبت‌های امروز را نشان می‌دهد و با یک لمس «مصرف کردم»
یا «جا افتاد» ثبت می‌شود؛ برنامه هیچ‌وقت خودش چیزی را «فراموش‌شده» نمی‌نامد.
کلید «این روزها سخت پیدا می‌شود» فقط یادداشت خودتان را نشان می‌دهد.

## Changelog

EN: The Today card counts the doses still open, and says when a day is
fully logged; each row names the next dose still ahead; "Me" joins the
person filter for a mixed household; doses logged from the detail sheet
now answer their routine moment everywhere, not only on the Today page;
the Today page marks the next moment to act on and stops locking the
whole page while one write is in flight; the duplicate-name question
says what the choice is; a routine naming both weekday and every-N-days
rules says which one counts; a long dose history opens on its newest
slice instead of building every row; and a Persian line that had stayed
English is Persian now.

FA: کارت «امروز» فقط نوبت‌های باز را می‌شمارد و وقتی همه ثبت شد، همان را
می‌گوید؛ هر سطر، نوبت بعدیِ پیش‌رو را نام می‌برد؛ «من» به صافی افراد
افزوده شده است؛ نوبت‌هایی که از صفحهٔ دارو ثبت می‌شوند حالا همه‌جا به
عنوان پاسخ همان ساعت شمرده می‌شوند، نه فقط در صفحهٔ امروز؛ صفحهٔ امروز
نوبت بعدی را مشخص می‌کند و هنگام هر ثبت، کل صفحه قفل نمی‌شود؛ پرسشِ
نامِ تکراری دقیقاً می‌گوید انتخاب چیست؛ برنامه‌ای که هم روز هفته و هم
«هر چند روز» دارد، می‌گوید کدام ملاک است؛ تاریخچهٔ طولانی نوبت‌ها با
تازه‌ترین بخش باز می‌شود؛ و یک جملهٔ فارسی که انگلیسی مانده بود، فارسی
شد.

EN (previous): Whose medicine it is, with a person filter; weekday and every-N-days
routines with start/end days; reminders planned from the routine that name the
medicine, the person and the time; a Today page with one-tap Taken/Skipped and
slot-accurate logs; a stock forecast with an editable early warning; boxes with
their own expiries and an Expiry page; a place/price/date log in tomans; an
opt-in secure window; and a person-owned "hard to find lately" note. Existing
records, logs, stocks, drafts and Undo behave exactly as before, and every
inherited test still passes.

FA (previous): نام صاحب دارو و صافی افراد؛ برنامهٔ روزهای هفته و «هر چند روز» با تاریخ
شروع و پایان؛ یادآورهای ساخته‌شده از برنامه که نام دارو، شخص و ساعت را
می‌گویند؛ صفحهٔ امروز با ثبت یک‌لمسی و نوبت‌های دقیق؛ پیش‌بینی موجودی با
هشدار قابل‌تنظیم؛ جعبه‌ها با انقضای مستقل و صفحهٔ انقضا؛ ثبت محل خرید، قیمت
به تومان و تاریخ؛ پنجرهٔ امن اختیاری؛ و یادداشت «سخت پیدا می‌شود» که فقط
خود شخص می‌گذارد. داده‌های قبلی، موجودی، پیش‌نویس و بازگردانی مثل قبل کار
می‌کنند و همهٔ آزمون‌های پیشین سبز مانده‌اند.

## Platform requests

Fulfilled, in the tree:

- Reviewed opt-in local notifications with permission/denial handling — the
  shared `NexModuleReminderControl` still sits on a medicine without times, and
  the upgrade arms concrete one-time alarms (`setReminder`) from the routine,
  withdrawing stale ones.
- Shared Jalali date entry and display — the expiry field still uses
  `NexModuleDateEntry`, and every day a person reads (expiry, box, place,
  today) goes through `nexModuleDateLabel`; storage stays civil ISO 8601.
- Shared multiline editor, `NexTextField`, `NexAutoDirection`, `NexPanel`,
  `NexAppBar`, `NexPageRoute` — used throughout, no local copies.
- `NexSecureWindow` — offered from the menu and acquired/released with the
  screen.

Still requested:

- Repeating reminders the OS owns (or a longer planning horizon). Today the
  module re-plans the next seven days whenever it is opened; a phone that is
  not opened for longer than that stops reminding until it is.
- A real atomic record-group/compare-and-write so two independent writers
  cannot interleave; the module journals and serialises its own writes.
- Permission-gated photos/scanning with backup retention, if boxes are ever to
  be captured rather than typed.
- Secure storage integration as required by core policy; the secure window is
  not encryption.

No clinical database/dosing API requested or improvised by this module.

## Device checklist

1. Add a medicine for a person, with two times, weekdays, a start day and
   warning days; reopen it and check the routine line reads back.
2. Turn notifications on, then lock the phone: each reminder must name the
   medicine, the person and the time, and must survive a force-stop and a
   phone restart (Doze included) for the planned days.
3. Leave the app closed overnight, open it the next morning: yesterday's
   unlogged moment appears under "yesterday, no record", not as "missed".
4. Log Taken from Today; the stock falls by the dose unit count; correct or
   delete the log and the stock comes back; try Skipped and confirm stock does
   not move.
5. Add a box that expired yesterday and one expiring in three days: both
   appear on the Expiry page and in the cabinet's expiry card.
6. Add a place with a toman price; check the grouping, Persian digits in
   Persian, and the Jalali day.
7. Turn the secure switch on: the app switcher/screenshot must hide the
   cabinet where the platform supports it; turn it off and confirm it is back.
   Rotate and kill the app between both states.
8. Archive a medicine: its reminders stop, it leaves Today and the counts, and
   its history stays. Delete one and Undo: boxes, places and logs return.
9. Persian/English, light/dark, text scale 2.0 and narrow screens; the editor's
   Save must stay reachable at 320×480 with 2× text.

## Open questions

- Should boxes count toward stock, or stay informational as they are now?
- Should the reminder's lock-screen text name the medicine and person by
  default, or should the person choose a quieter wording?
- Is a warning of 10 days right as the default for every medicine, or should
  the first-run value follow the routine (e.g. a week)?
- Should "hard to find lately" clear itself after a logged purchase, or only
  when the person turns it off?
- Should Today include yesterday by default, or only before noon?
- Do households want per-person reminder times, or is one routine per medicine
  enough?
- Should the price log show a total spent per medicine, or is the per-place
  history the honest limit without a budget feature?

## Checks

Completed in the audit pass (Linux, Flutter 3.47.9 / Dart 3.13.7, the
repository's own pinned SDK): `dart format` over the module's lib and test
folders; `flutter analyze --fatal-infos lib/modules/medicine
test/modules/medicine` — no issues; the module gate `flutter test
test/module_kit_test.dart test/modules/medicine` — all green, with the
module's suite grown from 106 to 133 (12 for the today progress logic, 13
for the audit's surfaces, 2 added to the shared-shape tests); the
inherited tests untouched and passing as they were. No lib file is over
400 lines (max 375) and the Persian words carry no bidi control
characters.

The `review/` screens are from the earlier upgrade pass, one release of
polish behind (they lack the next-dose marks). They were re-rendered and
checked in this pass but not committed; regenerating them is
`flutter test test/modules/medicine/screen_review_test.dart
--dart-define=NEX_CAPTURE=<dir>`. All are widget renders, not device
screenshots. Android/iOS permissions, native keyboards, TalkBack and
platform release builds are maintainer work, as is the device checklist
above.

Only this module's lib and test directories changed, plus the module
README and the user-facing changelogs. Registry, rollout, hero, ARB,
pubspec, module API and other modules are untouched.
