# The module kit

> How a module is written outside this repository (by another agent, or
> another person) and added without risk to the rest of the app. Read
> [`17-modules.md`](17-modules.md) first.

## The idea

A module from outside is **one folder of Dart and one folder of tests**.
Everything else is already there:

- adding it and removing it;
- the question about keeping or deleting its data;
- its card on the Modules page and its tile in Tools;
- its storage, and its place in backups.

The folder may import the module API and nothing past it. A test gate
checks that before anything else runs. So a module that is wrong is wrong
inside its own folder, and the worst it can do is show a bad screen. It
cannot:

- read a note, the vault or Cycle;
- open the network or the file system;
- change a setting;
- break the build of any other screen.

## What a module is made of

```
apps/client/lib/modules/<id>/
  module.dart        the class: extends NexStoredModule
  <screen>.dart …    its screens and logic, as many files as it needs
  README.md          what it does, its records, its words, guide and changelog lines
apps/client/test/modules/<id>/
  <id>_test.dart …   its own tests
```

`<id>` is lower-case letters, digits and `_` (`smoke_free`, `parking`). The
folder name and the module's `id` are the same.

### `module.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_screen.dart';

class ParkingModule extends NexStoredModule {
  const ParkingModule();

  @override
  String get id => 'parking';

  @override
  IconData get icon => Icons.local_parking_outlined;

  @override
  NexHue get hue => NexHue.sky;

  @override
  NexModuleStrings get strings => parkingStrings;

  @override
  Widget screen(NexModuleStore store) => ParkingScreen(store: store);
}
```

It defines nothing else. The title, tagline, about text and chips come from
`strings`, and adding and removing come from the base class.

### Words: `NexModuleStrings`

A module's words stay in the module, in both languages: two maps with the
same keys.

- **Required keys:**
  - `title`, `tagline` and `about`;
  - `point1` to `point4`, at least two of them. These are the chips on its
    card.
- **In a widget:** `strings(context, 'key')`.
- **With an argument:** `strings(context, 'count', {'count': 3})`. Numbers
  given as arguments come out in Persian digits on the Persian side.
- **Choosing a calendar:** `NexModuleStrings.persian(context)` says whether
  the app is showing Persian.

### Storage: `NexModuleStore`

The only storage a module has. Records are JSON objects filed under a
**kind** that the module chooses (`spot`, `word`, `receipt`) and an **id**.

| Call | |
|---|---|
| `list(kind)` | Every record of a kind, newest first, as `ModuleRecord`s (`id`, `body`, `updatedAt`). |
| `get(kind, id)` | One record's fields, or null. |
| `put(kind, id, body)` | Saves, replacing what was there. |
| `delete(kind, id)` | |
| `deleteRecords(records)` | Deletes several records as one storage transaction: either every one is gone, or none is. |
| `newId()` | A new unique, time-ordered id. |
| `changes` | Fires after this module's records change. A list screen listens to it. |

The kinds `__reminder` and `__recovery` belong to the platform; a
module's own `put` and `delete` refuse them. The reminder methods are the
sanctioned way to touch a reminder, and quarantine is the storage layer's.

Values are what JSON holds. A date is stored as `toIso8601String()`.
Records are:

- carried in every backup;
- never included in general search, embeddings, the note timeline or assistant tools;
- a first-party, explicit opt-in may expose a bounded projection to the smart
  brief; this exception never grants access to raw module records or history;
- deleted together when someone removes the module and chooses to delete.

### What the API gives

`module_api.dart` exports:

- `package:nex_ui/nex_ui.dart`: the tokens `NexSpacing`, `NexRadius` and
  `NexMotion`, `NexPageRoute`, the colour helpers, and the shared widgets;
- the shelf widgets (`NexPanel`, `NexShelfHeading`, `NexHue`, …);
- `NexMoreDetails` (`module_form.dart`) — the optional half of a form behind
  one button;
- `NexModuleHero` and `nexModuleAccent` (`module_hero.dart`) — the one hero
  that opens a module's home page, in the module's own colour;
- `nexShowSheet`, `nexShowDialog` and `NexDialogBody`;
- `NexTextField`, the shared multiline editor (native on Android);
- `nexPickModuleDate`, `NexModuleDateEntry` and `nexModuleDateLabel`, using the saved calendar while retaining civil dates at the storage boundary;
- `NexModuleReminderControl` and store reminder methods for explicit one-time OS alerts. Only available, installed modules may schedule them; removing a source record, archiving it or removing the module cancels its alarms. Requests are restored at launch. All stored modules remain Soon and silent in 2.1.3;
- `AppLocalizations`, for the shared words such as `cancel`;
- the module classes above.

Flutter's `material`, `widgets`, `foundation`, `animation`, `painting`,
`gestures` and `rendering` libraries, and `dart:async`, `math`, `convert`,
`collection` and `ui` may be imported too.

## Shared across modules (2.8.2)

Modules are separate folders, but to the person they are one app: the same
"Ali" in every module, the same money, the same dates falling due on one
calendar. These rules are what keeps that possible. Every module follows
them — the ones being written now and every one added later — and a
pull request that adds or upgrades a module is checked against them.

Some pieces are not in the kit yet. Until they are, a module copies the
**reference** named below, under the same file name and with the same
calls, so that the kit can later replace every copy in one move. It never
writes its own variant.

### 1. Dates that fall due: one shape, one calendar

Nex gathers every module's due dates into one shared calendar (the "life
calendar"). So:

- **No full calendar of a module's own.** A month list, or a simple month
  view of the module's own dates, is enough; the shared calendar component
  will replace it.
- **One function** produces everything a module has falling due — a cheque,
  an instalment, a dose, an insurance expiry, a payment day — for a range
  of days, with no widgets:

  ```dart
  /// Everything this module has falling due between [from] and [to].
  List<ModuleDue> duesBetween(DateTime from, DateTime to);
  ```

  | Field | Type | Meaning |
  |---|---|---|
  | `id` | `String` | stable, so the same item is the same item next time |
  | `recordKind`, `recordId` | `String` | the record it comes from, to open it |
  | `at` | `DateTime` | when it falls due (local; date-only items at midnight) |
  | `title` | `String` | what it is, in the person's own words where possible |
  | `kind` | `String` | the module's word for it (`cheque-in`, `dose`, …) |
  | `amountRial` | `int?` | money, when there is any; positive in, negative out |
  | `done` | `bool` | already paid, taken or cleared |
  | `private` | `bool` | health or money detail, shown only discreetly |

  `ModuleDue` is in the kit (`module_shared.dart`, through `module_api`)
  since 2.8.4, when the copies in each module's folder were replaced. The
  module's own screens and reminders use the same function, and it is
  unit-tested on its own: month ends, Esfand 29 and 30, a record missing a
  field.
- **The home screen reads it** (2.8.4): a module with dates overrides
  `NexStoredModule.dues(store, from, to)` — loading its records and calling
  its `duesBetween` — and, when a title alone does not say which date it is,
  `dueLabel(l10n, kind)`. «Dates from your tools» on the home screen lists
  what is late or falls due this week; a `private` item shows only its
  module's name, grouped, never its title or amount. Switched in Home
  layout. A tap on a line opens the module's quick view (below).
- **Many items, one line** (2.8.5): when a day's items are better said
  together («3 habits left today», «12 words to review»), `dues` returns one
  `ModuleDue` with an **empty title** and the count in its kind
  (`habits-today:3`); `dueLabel` phrases the kind in the page's language and
  the home card shows the label alone. `dues` never returns items before
  today that nobody can act on any more (a medicine dose of last week).
- **Days and tasks** (2.8.6): a due that is a day rather than something to
  do — a birthday, a warranty's end — sets `passes: true`; once its day has
  gone it leaves the card, the quick view and the assistant
  (`ModuleDue.isOver(today)`) instead of reading as late. A task (a cheque,
  an instalment, an expired insurance) stays until it is done, marked late.

### 2. Money

- Stored as a whole number of **rials**, in a field whose name ends in
  `Rial` (`amountRial`, `priceRial`). Never a floating-point number, never
  tomans.
- Foreign money is stored as `{"amount": <int, smallest unit>, "currency":
  "USD"}` with ISO 4217 codes.
- Shown in tomans or rials with Persian digits and grouping in Persian.
  Whether a person sees tomans or rials will become one setting for the
  whole app; until then the module follows the reference.
- **Reference:** `lent_borrowed/money_format.dart`, `amount_field.dart` and
  `currency_field.dart`.

### 3. People

- The other party — a borrower, a cheque's payee, a fund member, a family
  member taking a medicine — is stored in a field named **`person`**, as an
  object: `{"name": "Ali"}`. The object may later gain an `id` from the
  app's shared list of people; a module keeps it as it found it.
- Never a bare string in some fields and an object in others. A module
  that keeps people of its own (members, family) still stores each one's
  name under `person.name`.
- Card numbers and IBANs belong to a person (`person.cards`,
  `person.ibans`), never to the record that mentions them; never a CVV2,
  an expiry date, a PIN or a password.

### 4. A line about each record

So that module records can, later and only with the person's consent, be
found from the main search and mentioned by the daily brief, each module
has one plain function:

```dart
/// One line about [record], in the person's own words; null to keep it out.
ModuleSummary? summarize(ModuleRecord record);
```

with `ModuleSummary` = `title` (`String`), `detail` (`String?`) and
`private` (`bool`: health or money, never shown without opting in), in the
kit since 2.8.4. Today nothing reads it but the module's tests; module records are still never in
general search or the timeline.

### 4b. The module at a glance (2.8.5)

Every module that keeps records overrides

```dart
Future<ModuleGlance?> glance(
  NexModuleStore store, AppLocalizations l10n, DateTime now);
```

with `ModuleGlance` = `headline` (the one fact that matters now: «Next:
Rent cheque · in 3 days», «Tirajeh mall · -2 · B14»), `detail` (a line
under it), `progress` (0–1, drawn as a bar) and `facts`
(`ModuleGlanceFact(label, value, strong:)`). Before there is anything to
say it is the module's empty line («No cheques yet»), never null.

- **Where it shows:** the pinned tile (headline, detail), the **quick view**
  (`widgets/module_peek.dart`, `nexShowModulePeek`) that a tap on a pinned
  module or a dates-card line opens — the glance plus its open dates of the
  next month, with the module one button away — and, only after the person
  turns on «Let it see my tools», the assistant (`platform/tools_for_assistant.dart`).
- **Privacy:** a money module's headline and detail — what the tile on the
  home screen shows — carry no amount; amounts appear only among the quick
  view's facts, the way the module itself opens, and not at all where the
  module keeps «hide amounts» as a setting (Expenses). The Asset book's
  glance is always covered. The assistant gets nothing from the
  modules in `nexToolsKeptOnPhone` (money, health, belongings) but a count
  of what is due, and no `private` due of any module by title.
- **Words:** `glance*` keys in the module's own strings, both languages;
  money through `nexTomanText`, days through `nexDueWhen`.
- **Tested** in `test/module_glance_test.dart` (every module has one) and
  `test/tools_for_assistant_test.dart` (what leaves the phone).

### 5. Records keep what they do not know

Read old records defensively, and **write back every field you did not
change**, including ones your version does not know: a later version, or
the platform (a person's `id`), may have added them. Fields are added,
never renamed or removed.

### 6. Saving, leaving a form, undo

- Saving happens as the person types (`NexModuleFormDraft`,
  `NexCheckedModuleFormDraft`); leaving a half-written form keeps it.
- Deleting shows `nexShowBanner` with Undo.
- **Reference** for leaving a form with unsaved changes:
  `lent_borrowed/draft_guard.dart`.

### 7. Reminders

- Only through `NexModuleReminderControl` and the store's reminder calls.
- The words name the thing and when ("Cheque to Ali, 12,000,000 tomans:
  in 3 days"), never "You have a reminder".
- Lead times come from one set: on the day, and 1, 3, 7, 14 or 30 days
  before; a module picks its default from these.

### 8. Sharing, hiding, pictures

- Text is shared with `nexModuleShareText`. Image sharing is not in the
  kit; ask for it under Platform requests.
- A screen with money totals or health details can hide them; until the
  app has one setting for it, the module keeps its own `hideAmounts` and
  uses `NexSecureWindow` for health data.
- Photos (a cheque, an invoice, an insurance card) are not in the kit;
  ask for them, and keep a text reference meanwhile.

### 9. Look and movement

`docs/16-design-language.md` and `docs/26-ui-consistency.md`, and the
shared pieces they name: `NexAdaptiveSegments` for choices, `NexSegmentSwap`
for a segment that swaps the view below it, tabs that keep what was typed,
`heroTag: null` on every floating button, `NexModuleHero` at the top.

## The gate: `test/module_kit_test.dart`

For every folder under `lib/modules/`, the gate checks five things:

1. **Imports.** Every import is one of those above, or a file inside the
   module's own folder.
2. **Forbidden code.** No file:
   - overrides `open`, `turnOn`, `turnOff` or `isOn`;
   - names `NexServices` or `NexPreferences`;
   - opens a platform channel;
   - calls `showModalBottomSheet` or `showDialog` (it uses `nexShowSheet` and
     `nexShowDialog`).
3. **Files.** It has a `README.md`, and tests under `test/modules/<id>/`.
4. **Registry.** It is in `nexModules`.
5. **Words.** Both languages have the same keys, every required key is there,
   and no value is empty.

Beside it, `test/module_shared_rules_test.dart` holds the rules of
"Shared across modules": a module that sets reminders gives its due dates
through `duesBetween`, every module has `summarize`, and no money field in
rials can hold a fraction. Modules written before 2.8.2 are listed as
pending; the lists only shrink, and a new module meets the rules from its
first commit.

The gate also runs the worked example, `test/module_kit/tally/`: a tally
counter that is added, used, removed keeping its data, and removed deleting
it. Copying that is the fastest way to start.

## What a module cannot do yet

The following are deliberately outside the API until a module needs them:

- location;
- the camera and photos;
- network access;
- home-screen widgets;
- assistant tools;
- links into notes.

A module that needs one of them builds everything else, and lists the need
under **Platform requests** in its README. That API is then added here, by
the maintainers, in its own pull request, and the module uses it from then
on. The platform grows only by what a real module asked for.

## Adding a module someone else wrote

1. Unzip it into `apps/client/`. `git status` must show only
   `lib/modules/<id>/` and `test/modules/<id>/`; anything else is refused.
2. Add one line to `nexModules` in `module_registry.dart`, with its import.
3. Run the gate and the module's tests:

   ```
   flutter test test/module_kit_test.dart test/modules/<id>
   ```

   Then run the full checks (`make check-dart`, `flutter analyze`,
   `flutter test`).
4. Read the diff as a review: design language, both languages, light and
   dark, large text, and that it does what its README says.
5. Take the guide paragraph and the changelog lines from its README into the
   guide and the changelogs. Remove it from `module_plans.dart` if it was
   listed there.

The prompt to give the agent that writes a module is
[`prompts/11-module-builder.md`](prompts/11-module-builder.md).

Draft writes have their own `draftChanges` stream; `changes` is for saved data.
Journal and `__recovery` writes do not wake list readers. Draft helpers coalesce
typing for 250 ms and flush on close; final save/discard waits for in-flight
writes before cleanup, and an untouched form writes no checkpoint at all. A
compound delete runs as one storage transaction (`deleteRecords`); the journals
older versions wrote are still replayed on open, and unknown or malformed ones
are copied to `__recovery` before leaving the active queue. Raw undecodable
database bodies are preserved there byte-for-byte. Never replay a partly
validated journal.

A write reconciles only the reminders pointing at what it changed: a module
that saves a record its reminder cites finds that reminder re-armed (or, if the
source is gone, cancelled) when the write resolves, and no other module's
alarms are touched. Startup and resume still rebuild every module's reminders.
A daily reminder keeps the face of the clock it was set for; one written before
that was kept falls back to the stored instant.


## Habit briefs and notification destinations (2.5.1)

Habits enter the home smart brief and daily-summary notification only when
`brief.useHabits` is explicitly enabled (off by default) and the module is on.
`HabitsBrief` projects at most 12 relevant active habits into names, schedules,
goals, current progress and aggregate weekly consistency. Notes, descriptions
and raw check history stay local. The same AI request receives that projection;
no extra AI request is made. Report mode uses local progress within its existing
line budget.

Mixed AI caches are marked and a separate notes-only fallback is preserved.
Disabling consent hides mixed caches immediately, rejects mixed requests already
in flight and replaces the scheduled daily-summary body. It never disables the
brief itself or an individual habit reminder.

Module reminder payloads carry module, record kind/id, reminder key and day.
A shared destination resolver handles cold and warm launches; the app lock holds
the destination until unlock. Disabled modules stay disabled, and removed or
archived items fall back to their module with an explanation.

Binary habit notifications queue an idempotent completion per habit/day before
being dismissed. The existing service graph applies the queue and rearms the
habit reminder. Amount-based habits open the existing progress form without
saving automatically. Snooze reuses the same destination and notification text,
tries exact then inexact scheduling, and preserves the original notification if
both fail. Reminder text metadata is pruned daily after 14 days.

## Notices and reminder upkeep (2.5.2)

Use `nexShowBanner` or a captured `NexBannerHost` for in-app feedback. The
module API exports both; preserve Undo callbacks, action keys and the intended
notice lifetime. Do not use `SnackBar` or `ScaffoldMessenger.showSnackBar`.

Automatic reminder upkeep uses `NexModuleStore.withdrawReminder` when a slot
no longer has a future alarm; it preserves an already shown device notification.
Explicit removal or disabling a reminder still uses `clearReminder`. Startup
and resume run upkeep before restoring/pruning alarms through the shared
`nexRefreshReminders` flight, preventing a new alarm from being pruned against
an earlier module snapshot.
